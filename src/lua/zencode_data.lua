-- This file is part of Zenroom (https://zenroom.dyne.org)
--
-- Copyright (C) 2018-2019 Dyne.org foundation
-- designed, written and maintained by Denis Roio <jaromil@dyne.org>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as
-- published by the Free Software Foundation, either version 3 of the
-- License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.



--- Zencode data internals


-- init schemas
function ZEN.add_schema(arr)
   local _illegal_schemas = { -- const
	  whoami = true
   }
   for k,v in pairs(arr) do
	  -- check overwrite / duplicate to avoid scenario namespace clash
	  ZEN.assert(not ZEN.schemas[k], "Add schema denied, already registered schema: "..k)
	  ZEN.assert(not _illegal_schemas[k], "Add schema denied, reserved name: "..k)
	  ZEN.schemas[k] = v
   end
end


function ZEN.find_schema(name)
   -- returns a table with function pointers and string desc
   -- { fun   = conversion function pointer
   --   name  = conversion string description 
   -- }
   local res = { }
   res.fun = ZEN.schemas[name]
   if not res.fun then
	  xxx("Schema not found: "..(name or 'nil'), 2);
	  return nil
   end
   res.name = name
   return res
end


-- -- basic encoding schemas
-- ZEN.add_schema({
-- 	  base64 = function(obj) return ZEN:convert(obj, OCTET.from_base64) end,
-- 	  url64  = function(obj) return ZEN:convert(obj, OCTET.from_url64)  end,
-- 	  hex =    function(obj) return ZEN:convert(obj, OCTET.from_hex) end,
-- 	  str =    function(obj) return ZEN:convert(obj, OCTET.from_string) end,
-- })

-- init statements
function Given(text, fn)
   ZEN.assert(not ZEN.given_steps[text],
   			  "Conflicting statement loaded by scenario: "..text)
   ZEN.given_steps[text] = fn
end
function When(text, fn)
   ZEN.assert(not ZEN.when_steps[text],
   			  "Conflicting statement loaded by scenario: "..text)
   ZEN.when_steps[text] = fn
end
function Then(text, fn)
   ZEN.assert(not ZEN.then_steps[text],
   			  "Conflicting statement loaded by scenario : "..text)
   ZEN.then_steps[text] = fn
end

-- the main security concern in this Zencode module is that no data
-- passes without validation from IN to ACK or from inline input.

-- TODO: return the prefix of an encoded string if found
ZEN.prefix = function(str)
   t = type(str)
   if t ~= "string" then return nil end
   if str:sub(4,4) ~= ":" then return nil end
   return str:sub(1,3)
end

-- TODO: ZEN.cast to zenroom. type
ZEN.get = function(obj, key, conversion)
   ZEN.assert(obj, "ZEN.get no object found")
   ZEN.assert(type(key) == "string", "ZEN.get key is not a string")
   ZEN.assert(not conversion or type(conversion) == 'function',
			  "ZEN.get invalid conversion function")
   local k
   if key == "." then
      k = obj
   else
      k = obj[key]
   end
   ZEN.assert(k, "Key not found in object conversion: "..key)
   local res = nil
   local t = type(k)
   if iszen(t) and conversion then res = conversion(k) goto ok end
   if iszen(t) and not conversion then res = k goto ok end
   if t == 'string' then
      res = CONF.input.encoding.fun(k)
      if conversion then res = conversion(res) end
      goto ok
   end
   if t == 'number' then res = k end
   -- TODO: table
   ::ok::
   assert(ZEN.OK and res, "ZEN.get on invalid key: "..key.." ("..t..")")
   return res
end


-- import function to have recursion of nested data structures
-- according to their stated schema
function ZEN:valid(sname, obj)
   ZEN.assert(sname, "Import error: schema name is nil")
   ZEN.assert(obj, "Import error: object is nil '"..sname.."'")
   local s = ZEN.schemas[sname]
   ZEN.assert(s, "Import error: schema not found '"..sname.."'")
   ZEN.assert(type(s) == 'function', "Import error: schema is not a function '"..sname.."'")
   return s(obj)
end

--- Given block (IN read-only memory)
-- @section Given

---
-- Declare 'my own' name that will refer all uses of the 'my' pronoun
-- to structures contained under this name.
--
-- @function ZEN:Iam(name)
-- @param name own name to be saved in WHO
function ZEN:Iam(name)
   if name then
	  ZEN.assert(not WHO, "Identity already defined in WHO")
	  ZEN.assert(type(name) == "string", "Own name not a string")
	  WHO = name
   else
	  ZEN.assert(WHO, "No identity specified in WHO")
   end
   assert(ZEN.OK)
end

---
-- Guess how to convert the object, using what format or schema
-- check the definition string (coming straight from zencode)
-- considering the type of the object:
-- ```
-- type    def       conv
-- ------------------------------------------------------
-- str     ===       default_encoding
-- str     format    input_encoding(format)
-- str     schema    schema_f(..., default_encoding)
-- num     (number)  num
-- table   ===       deepmap(table, default_encoding)
-- table   format    deepmap(table, input_encoding(format))
-- table   schema    schema_f(table, default_encoding)
-- ```
-- returns a table with function pointers and string desc that
-- will be used by operate conversion
-- { fun   = conversion function pointer
--   name  = conversion string description 
--   check = check function pointer
--   istable = true -- if deepmap required
--   isschema = true -- if schema function required
-- }
function guess_conversion(objtype, definition)
   definition = definition or CONF.input.encoding.name
   -- assert(definition, "Internal error: guess_conversion needs 2 arguments", 2)
   local res = { }
   local t
   -- map to check if format string exists
   local formats = { hex=1, bin=1, base64=1, url64=1, base58=1 }
   -- ZEN.schemas is the other map to check
   if objtype == 'string' then
       t = input_encoding(definition)
       -- t = { name, fun, check}
       if t then
         res = { name = t.name,
               fun = t.fun,
               check = t.check }
       else
         t = ZEN.schemas[definition]
         -- t = function pointer
         if t then
            res = { fun = t,
                  isschema = true,
                  name = definition } -- also t.name
                  -- check = nil
         end
      end
		if not res then
			error('String conversion not found: '..definition, 2)
			return nil
		end
      res.istable = nil -- no deepmap for single string
      
   elseif objtype == 'number' then
	   res = { fun = tonumber,
            check = tonumber,
            name = 'number' }

   elseif objtype == 'table' then
		t = input_encoding(definition)
      if t then
         res = { istable = true,
               name = t.name,
               fun = t.fun,
               check = t.check }
         -- isschema = nil
      else
         t = ZEN.schemas[definition]
         if t then
            res = { fun = t,
                  isschema = true,
                  name = definition }
         end
      end
      if not res then
			error('Table conversion not found: '..definition, 2)
			return nil
      end
      
   else
	  error('Unrecognized object type in Given conversion',2)
	  return nil
   end
   return res
end

-- takes a data object and the guessed structure, operates the
-- conversion and returns the resulting raw data to be used inside the
-- WHEN block in HEAP.
function operate_conversion(data, guessed)
   if not guessed.fun then
	  error('No conversion operation guessed: '..guessed.name, 2)
	  return nil
   end
   xxx('Operating conversion on: '..guessed.name)
   if guessed.istable then
	  -- TODO: better error checking on deepmap?
	  return deepmap(guessed.fun, data)
   elseif guessed.isschema then
	  return guessed.fun(data)
   else
	  if guessed.check then
		 if not guessed.check(data) then
			error('Conversion check failed for data: '..guessed.name, 2)
			return nil
		 end
	  end
   end
   return guessed.fun(data)
end

local function save_array_codec(n)
	local toks = strtok(n)
	if toks[2] == 'array' then

   else
      return nil
   end
end

---
-- Pick a generic data structure from the <b>IN</b> memory
-- space. Looks for named data on the first and second level and makes
-- it ready in TMP for @{validate} or @{ack}.
--
-- @function ZEN:pick(name, data, encoding)
-- @param what string descriptor of the data object
-- @param obj[opt] optional data object (default search inside IN.*)
-- @param conv[opt] optional encoding spec (default CONF.input.encoding)
-- @return true or false
function ZEN:pick(what, obj, conv)
   local guess
   if obj then -- object provided by argument
      TMP.root = nil
      -- guess = { fun, check, name(type)
      --           istable, isschema      }
	   TMP.guess = guess_conversion(type(obj), conv)
      TMP.data = TMP.operate_conversion(obj, TMP.guess)
      TMP.schema = TMP.guess.name
      -- local toks = strtok(what,'[^_]+')
	   return(ZEN.OK)
   end
   local got
   got = IN.KEYS[what] or IN[what]
   ZEN.assert(got, "Cannot find '"..what.."' anywhere")
   if not conv and ZEN.schemas[what] then conv = what end
   TMP.guess = guess_conversion(type(got), conv)
   ZEN.assert(TMP.guess, "Cannot guess any conversion for: "..
				  type(got).." "..(conv or "(nil)"))
   TMP.root = nil
   TMP.data = operate_conversion(got, TMP.guess)
   TMP.schema = TMP.guess.name
   assert(ZEN.OK)
   ZEN:ftrace("pick found "..what)
end

---
-- Pick a data structure named 'what' contained under a 'section' key
-- of the at the root of the <b>IN</b> memory space. Looks for named
-- data at the first and second level underneath IN[section] and moves
-- it to TMP[what][section], ready for @{validate} or @{ack}. If
-- TMP[what] exists already, every new entry is added as a key/value
--
-- @function ZEN:pickin(section, name)
-- @param section string descriptor of the section containing the data
-- @param what string descriptor of the data object
-- @param conv string explicit conversion or schema to use
-- @param fail bool bail out or continue on error
-- @return true or false
function ZEN:pickin(section, what, conv, fail)
   ZEN.assert(section, "No section specified")
   local root -- section
   local got  -- what
   local bail -- fail
   root = IN.KEYS[section]
   if root then
	  got = root[what]
	  if got then goto found end
   end
   root = IN[section]
   if root then
	  got = root [what]
	  if got then goto found end
   end
   if got then goto found end -- success condition
   if bail then
	  ZEN.assert(got, "Cannot find '"..what.."' inside '"..section.."'")
   else return false end
   -- TODO: check all corner cases to make sure TMP[what] is a k/v map
   ::found::
   -- conv = conv or what
   root = nil
   if not conv and ZEN.schemas[what] then conv = what end
   TMP.guess = guess_conversion(type(got), conv )
   TMP.root = section
	TMP.data = operate_conversion(got, TMP.guess)
	TMP.schema = TMP.guess.name
   assert(ZEN.OK)
   ZEN:ftrace("pickin found "..what.." in "..section)
end


function ZEN:get_schema(obj, name)
   ZEN.assert(name, "ZEN:get_schema error: schema name is nil")
   ZEN.assert(obj, "ZEN:get_schema error: object is nil")
   local s = ZEN.schemas[name]
   ZEN.assert(s, "ZEN:get_schema error: schema not found: "..name)
   ZEN.assert(type(s) == 'function', "ZEN:get_schema error: schema is not a function: "..name)
   ZEN:ftrace("get_schema "..name)
   local res = s(obj)
   ZEN.assert(res, "Recursive schema conversion failed: "..name)
   return(res)
end

function ZEN:ack_table(key,val)
   ZEN.assert(type(key) == 'string',"ZEN:table_add arg #1 is not a string")
   ZEN.assert(type(val) == 'string',"ZEN:table_add arg #2 is not a string")
   if not ACK[key] then ACK[key] = { } end
   ACK[key][val] = TMP.data
end

---
-- Final step inside the <b>Given</b> block towards the <b>When</b>:
-- pass on a data structure into the ACK memory space, ready for
-- processing.  It requires the data to be present in TMP[name] and
-- typically follows a @{pick}. In some restricted cases it is used
-- inside a <b>When</b> block following the inline insertion of data
-- from zencode.
--
-- @function ZEN:ack(name)
-- @param name string key of the data object in TMP[name]
function ZEN:ack(name)
   ZEN.assert(TMP.data, "No valid object found: ".. name)
   -- CODEC[what] = CODEC[what] or {
   --    name = guess.name,
   --    istable = guess.istable,
   --    isschema = guess.isschema }

   assert(ZEN.OK)
   local t = type(ACK[name])
   if not ACK[name] then -- assign in ACK the single object
	  ACK[name] = TMP.data
	  goto done
   end
   -- ACK[name] already holds an object
   -- not a table?
   if t ~= 'table' then -- convert single object to array
	  ACK[name] = { ACK[name] }
	  table.insert(ACK[name], TMP.data)
	  goto done
   end
   -- it is a table already
   if isarray(ACK[name]) then -- plain array
	  table.insert(ACK[name], TMP.data)
	  goto done
   else -- associative map
	  table.insert(ACK[name], TMP.data) -- TODO: associative map insertion
	  goto done
   end
   ::done::
   assert(ZEN.OK)
end

function ZEN:ackmy(name, object)
   local obj = object or TMP.data
   ZEN:trace("f   pushmy() "..name.." "..type(obj))
   ZEN.assert(WHO, "No identity specified")
   ZEN.assert(obj, "Object not found: ".. name)
   local me = WHO
   if not ACK[me] then ACK[me] = { } end
   ACK[me][name] = obj
   assert(ZEN.OK)
end

---
-- Compare equality of two data objects (TODO: octet, ECP, etc.)
-- @function ZEN:eq(first, second)

---
-- Check that the first object is greater than the second (TODO)
-- @function ZEN:gt(first, second)

---
-- Check that the first object is lesser than the second (TODO)
-- @function ZEN:lt(first, second)


--- Then block (OUT write-only memory)
-- @section Then

---
-- Move a generic data structure from ACK to OUT memory space, ready
-- for its final JSON encoding and print out.
-- @function ZEN:out(name)

---
-- Move 'my own' data structure from ACK to OUT.whoami memory space,
-- ready for its final JSON encoding and print out.
-- @function ZEN:outmy(name)

---
-- Convert a data object to the desired format (argument name provided
-- as string), or use CONF.encoding when called without argument
--
-- @function export_obj(object, format)
-- @param object data element to be converted
-- @param format pointer to a converter function
-- @return object converted to format
local function export_arr(object, format)
   ZEN.assert(iszen(type(object)), "export_arr called on a ".. type(object))
   local conv_f = nil
   local ft = type(format)
   if format and ft == 'function' then conv_f = format goto ok end
   if format and ft == 'string' then conv_f = output_encoding(format).fun goto ok end
   conv_f = CONF.output.encoding.fun -- fallback to configured conversion function
   ::ok::
   ZEN.assert(type(conv_f) == 'function' , "export_arr conversion function not configured")
   return conv_f(object) -- TODO: protected call? deepmap?
end
function export_obj(object, format)
   -- CONF { encoding = <function 1>,
   --        encoding_prefix = "u64"  }
   ZEN.assert(object, "export_obj object not found")
   if type(object) == 'table' then
	  local tres = { }
	  for k,v in ipairs(object) do -- only flat tables support recursion
		 table.insert(tres, export_arr(v, format))
	  end
	  return tres
   end
   return export_arr(object, format)
end

local function pfx(o) return string.sub(o,1,3) end
local function buf(o) return string.sub(o,5) end

---
-- Decode a format encoded object using the provided decoder or the
-- default CONF.encoding
-- Table format of the decoder:
-- ```
-- { fun = pointer to conversion function
--   name = short string name
--   check = pointer to check function }
-- ```
--
-- @function ZEN.decode(anystr, decoder)
-- @param anystr data element to be read
-- @param decoder table describing the conversion
-- @return octet object decoded
function ZEN.decode(anystr, decoder)
   ZEN.assert(anystr, "ZEN.decode object is nil")
   local t = type(anystr)   
   if iszen(t) then
      warn("ZEN.decode input already decoded to "..t)
      return t
   end
   ZEN.assert(t == 'string' or t == 'number' or t == 'table',
			  "ZEN.decode input not a string or number or table: "..t)
   -- anystr is a valid conversion value

   local dec = decoder or CONF.input.encoding

   if t == 'number' then
	  if dec.name ~= 'number' then
		 error("wrong decoder for raw number data: "..dec.name, 3)
		 return nil
	  end
	  return( anystr )
   end

   if not dec.fun then
	  error("Invalid decoder (no CONF.input.encoding.fun)", 3)
	  return nil
   end

   xxx("Data type "..t.." selected decoder: "..dec.name, 3)
   if t == 'table' then
	  return( deepmap(dec.fun, anystr) )
   else
	  return( dec.fun(anystr) )
   end
end


