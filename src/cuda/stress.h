
#ifndef _STRESS_KERNEL_
#define _STRESS_KERNEL_

#include "particledefine.h"
#include "textures.cuh"
#include "multi_gpu_defines.h"

namespace cudensity_sum {

using namespace cusph;
using namespace cuphys;
using namespace cuneibs;
using namespace cueuler;

struct stress_particle_output
{
float4	gGamNp1;
float		rho;

__device__ __forceinline__
density_sum_particle_output() :
	gGamNp1(make_float4(0.0f)),
	rho(0.0f)
{}
};

struct common_density_sum_particle_data
{
const	uint	index;
const	particleinfo	info;
const	ParticleType	ptype;
const	float4	force;
const	int3	gridPos;
const	float4	posN;
const	float4	posNp1;
const	float4	vel;
const	float4	gGamN;

__device__ __forceinline__
common_density_sum_particle_data(const uint _index, common_density_sum_params const& params) :
	index(_index),
	info(params.info[index]),
	ptype(static_cast<ParticleType>(PART_TYPE(info))),
	force(params.forces[index]),
	gridPos(calcGridPosFromParticleHash(params.particleHash[index])),
	posN(params.oldPos[index]),
	posNp1(params.newPos[index]),
	vel(params.oldVel[index]),
	gGamN(params.oldgGam[index])
{}
};