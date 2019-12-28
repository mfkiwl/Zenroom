/* This file is part of Zenroom (https://zenroom.dyne.org)
 *
 * Copyright (C) 2017-2019 Dyne.org foundation
 * designed, written and maintained by Denis Roio <jaromil@dyne.org>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */


/// <h1>Cryptographically Secure Random Number Generator (RNG)</h1>
//
// Each new RNG instance is initialised with a different random seed
//
// Cryptographic security is achieved by hashing the random numbers
// using this sequence: unguessable seed -> SHA -> PRNG internal state
// -> SHA -> random numbers. See <a
// href="ftp://ftp.rsasecurity.com/pub/pdfs/bull-1.pdf">this paper</a>
// for an exstensive description of the process. More recent methods
// (fortuna etc) are in the works.
//
// @module RNG
// @author Denis "Jaromil" Roio
// @license GPLv3
// @copyright Dyne.org foundation 2017-2019

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <jutils.h>
#include <zen_error.h>
#include <lua_functions.h>

#include <time.h>

#include <amcl.h>

// easier name (csprng comes from amcl.h in milagro)
#define RNG csprng

#include <zenroom.h>
#include <zen_memory.h>
#include <randombytes.h>

extern zenroom_t *Z;
extern zen_mem_t *MEM;
// small buffer pre-filled with random, used at runtime by some
// internal functions esp. to wipe out memory (lstring.c)
char *runtime_random256 = NULL;

void* rng_alloc() {
	HERE();
	RNG *rng = (RNG*)(*MEM->malloc)(sizeof(csprng));
	if(!rng) {
		lerror(NULL, "Error allocating new random number generator in %s",__func__);
		return NULL; }

	// random seed provided externally 
	if(Z->random_seed) {
		act(Z->lua,"Random seed is external, deterministic execution");
		if(!Z->random_generator) {
			// TODO: feed minimum 128 bytes
			RAND_seed(rng, Z->random_seed_len, Z->random_seed);
			// Z->random_generator is allocated only once and freed in
			// zen_teardown, lasts for the whole execution
			Z->random_generator = (*MEM->malloc)(sizeof(csprng)+8);
			memcpy(Z->random_generator, rng, sizeof(csprng));
		} else {
			memcpy(rng, Z->random_generator, sizeof(csprng));
		}
#ifndef ARCH_CORTEX
	} else {
		// gather system random using randombytes()
		char *tmp = (*MEM->malloc)(256);
		randombytes(tmp,252);
		// using time() from milagro
		unsign32 ttmp = (unsign32)time(NULL);
		tmp[252] = (ttmp >> 24) & 0xff;
		tmp[253] = (ttmp >> 16) & 0xff;
		tmp[254] = (ttmp >>  8) & 0xff;
		tmp[255] =  ttmp & 0xff;
		RAND_seed(rng,256,tmp);
		(*MEM->free)(tmp);
#endif
	}
	return(rng);
}


static int rng_uint8(lua_State *L) {
	uint8_t res = RAND_byte(Z->random_generator);
	lua_pushinteger(L, (lua_Integer)res);
	return(1);
}

static int rng_uint16(lua_State *L) {
	uint16_t res =
		RAND_byte(Z->random_generator)
		| (uint32_t) RAND_byte(Z->random_generator) << 8;
	lua_pushinteger(L, (lua_Integer)res);
	return(1);
}

static int rng_int32(lua_State *L) {
	uint32_t res =
		RAND_byte(Z->random_generator)
		| (uint32_t) RAND_byte(Z->random_generator) << 8
		| (uint32_t) RAND_byte(Z->random_generator) << 16
		| (uint32_t) RAND_byte(Z->random_generator) << 24;
	lua_pushinteger(L, (lua_Integer)res);
	return(1);
}

void zen_add_random(lua_State *L) {
	static const struct luaL_Reg rng_base [] =
		{ {"random_int8",  rng_uint8  },
		  {"random_int16", rng_uint16 },
		  {"random_int32", rng_int32 },
		  {"random8",  rng_uint8  },
		  {"random16", rng_uint16 },
		  {"random32", rng_int32 },
		  {"random",  rng_uint16  },
		  {NULL, NULL} };
	lua_getglobal(L, "_G");
	luaL_setfuncs(L, rng_base, 0);
	lua_pop(L, 1);

	{ // pre-fill runtime_random
		// used in
		register int i;
		runtime_random256 = system_alloc(256);
		char *p = runtime_random256;
		for(i=0;i<256;i++,p++) *p = RAND_byte(Z->random_generator);
	}

}
