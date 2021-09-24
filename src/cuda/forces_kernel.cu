/*  Copyright (c) 2011-2019 INGV, EDF, UniCT, JHU

    Istituto Nazionale di Geofisica e Vulcanologia, Sezione di Catania, Italy
    Électricité de France, Paris, France
    Università di Catania, Catania, Italy
    Johns Hopkins University, Baltimore (MD), USA

    This file is part of GPUSPH. Project founders:
        Alexis Hérault, Giuseppe Bilotta, Robert A. Dalrymple,
        Eugenio Rustico, Ciro Del Negro
    For a full list of authors and project partners, consult the logs
    and the project website <https://www.gpusph.org>

    GPUSPH is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    GPUSPH is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with GPUSPH.  If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * Device code.
 */

#ifndef _FORCES_KERNEL_
#define _FORCES_KERNEL_

#include "particledefine.h"
#include "textures.cuh"
#include "vector_math.h"
#include "multi_gpu_defines.h"
#include "GlobalData.h"

#include "kahan.h"
#include "tensor.cu"

#include "device_core.cu"

//#include "visc_kernel.cu"


#if __COMPUTE__ < 20
#define printf(...) /* eliminate printf from 1.x */
#endif

// Single-precision M_PI
// FIXME : ah, ah ! Single precision with 976896587958795795 decimals ....
#define M_PIf 3.141592653589793238462643383279502884197169399375105820974944f

#define MAXKASINDEX 10

/** \namespace cuforces
 *  \brief Contains all device functions/kernels/variables used force computations, filters and boundary conditions
 *
 *  The namespace cuforces contains all the device part of force computations, filters and boundary conditions :
 *  	- device constants/variables
 *  	- device functions
 *  	- kernels
 *
 *  \ingroup forces
 */
namespace cuforces {

using namespace cugeom;
using namespace cusph;
using namespace cuphys;
using namespace cuneibs;
//using namespace cuvisc;

// Core SPH functions
/** \name Device constants
 *  @{ */
// Rigid body data
__constant__ int3	d_rbcgGridPos[MAX_BODIES]; //< cell of the center of gravity
__constant__ float3	d_rbcgPos[MAX_BODIES]; //< in-cell coordinate of the center of gravity
__constant__ int	d_rbstartindex[MAX_BODIES];
/*  @} */

/** \name Device functions
 *  @{ */

/************************************************************************************************************/
/*							  Functions used by the different CUDA kernels							        */
/************************************************************************************************************/

//! Lennard-Jones boundary repulsion force
__device__ __forceinline__ float
LJForce(const float r)
{
	float force = 0.0f;

	if (r <= d_r0)
		force = d_dcoeff*(__powf(d_r0/r, d_p1coeff) - __powf(d_r0/r, d_p2coeff))/(r*r);

	return force;
}

//! Monaghan-Kajtar boundary repulsion force
/*!
 Monaghan-Kajtar boundary repulsion force doi:10.1016/j.cpc.2009.05.008
 to be multiplied by r_aj vector
 we allow the fluid particle mass mass_f to be different from the
 boundary particle mass mass_b even though they are typically the same
 (except for multi-phase fluids)
*/
__device__ __forceinline__ float
MKForce(const float r, const float slength,
		const float mass_f, const float mass_b)
{
	// MK always uses the 1D cubic or quintic Wendland spline
	float w = 0.0f;

	float force = 0.0f;

	// Wendland has radius 2
	if (r <= 2*slength) {	//TODO: fixme use influenceradius
		float qq = r/slength;
		w = 1.8f * __powf(1.0f - 0.5f*qq, 4.0f) * (2.0f*qq + 1.0f);  //TODO: optimize
		// float dist = r - d_MK_d;
		float dist = max(d_epsartvisc, r - d_MK_d);
		force = d_MK_K*w*2*mass_b/(d_MK_beta * dist * r * (mass_f+mass_b));
	}

	return force;
}
/************************************************************************************************************/

/******************** Functions for computing repulsive force directly from DEM *****************************/

// TODO: check for the maximum timestep

//! Computes normal and viscous force wrt to solid planar boundary
__device__ __forceinline__ float
PlaneForce(	const int3&		gridPos,
			const float3&	pos,
			const float		mass,
			const plane_t&	plane,
			const float3&	vel,
			const float		dynvisc,
			float4&			force)
{
	// relative position of our particle from the reference point of the plane
	const float r = PlaneDistance(gridPos, pos, plane);
	if (r < d_r0) {
		const float DvDt = LJForce(r);
		// Unitary normal vector of the surface
		const float3 relPos = plane.normal*r;

		as_float3(force) += DvDt*relPos;

		// tangential velocity component
		const float3 v_t = vel - dot(vel, relPos)/r*relPos/r; //TODO: check

		// f = -µ u/∆n

		// viscosity
		// float coeff = -dynvisc*M_PI*(d_r0*d_r0-r*r)/(pos.w*r);
		// float coeff = -dynvisc*M_PI*(d_r0*d_r0*3/(M_PI*2)-r*r)/(pos.w*r);
		const float coeff = -dynvisc*d_partsurf/(mass*r);

		// coeff should not be higher than needed to nil v_t in the maximum allowed dt
		// coefficients are negative, so the smallest in absolute value is the biggest

		/*
		float fmag = length(as_float3(force));
		float coeff2 = -sqrt(fmag/slength)/(d_dtadaptfactor*d_dtadaptfactor);
		if (coeff2 < -d_epsartvisc)
			coeff = max(coeff, coeff2);
			*/

		as_float3(force) += coeff*v_t;

		return -coeff;
	}

	return 0.0f;
}

//! DOC-TODO Describe function
__device__ __forceinline__ float
GeometryForce(	const int3&		gridPos,
				const float3&	pos,
				const float		mass,
				const float3&	vel,
				const float		dynvisc,
				float4&			force)
{
	float coeff_max = 0.0f;
	for (uint i = 0; i < d_numplanes; ++i) {
		float coeff = PlaneForce(gridPos, pos, mass, d_plane[i], vel, dynvisc, force);
		if (coeff > coeff_max)
			coeff_max = coeff;
	}

	return coeff_max;
}

//! DOC-TODO describe function
__device__ __forceinline__ float
DemLJForce(	const texture<float, 2, cudaReadModeElementType> texref,
			const int3&	gridPos,
			const float3&	pos,
			const float		mass,
			const float3&	vel,
			const float		dynvisc,
			float4&			force)
{
	const float2 demPos = DemPos(gridPos, pos);

	const float globalZ = d_worldOrigin.z + (gridPos.z + 0.5f)*d_cellSize.z + pos.z;
	const float globalZ0 = DemInterpol(texref, demPos);

	if (globalZ - globalZ0 < d_demzmin) {
		const plane_t demPlane(DemTangentPlane(texref, gridPos, pos, demPos, globalZ0));

		return PlaneForce(gridPos, pos, mass, demPlane, vel, dynvisc, force);
	}
	return 0;
}

/************************************************************************************************************/

/************************************************************************************************************/
/*		Device functions used in kernels other than the main forces kernel									*/
/************************************************************************************************************/

//! contribution of neighbor at relative position relPos with weight w to the MLS matrix mls
__device__ __forceinline__ void
MlsMatrixContrib(symtensor4 &mls, float4 const& relPos, float w)
{
	mls.xx += w;						// xx = ∑Wij*Vj
	mls.xy += relPos.x*w;				// xy = ∑(xi - xj)*Wij*Vj
	mls.xz += relPos.y*w;				// xz = ∑(yi - yj)*Wij*Vj
	mls.xw += relPos.z*w;				// xw = ∑(zi - zj)*Wij*Vj
	mls.yy += relPos.x*relPos.x*w;		// yy = ∑(xi - xj)^2*Wij*Vj
	mls.yz += relPos.x*relPos.y*w;		// yz = ∑(xi - xj)(yi - yj)*Wij*Vj
	mls.yw += relPos.x*relPos.z*w;		// yz = ∑(xi - xj)(zi - zj)*Wij*Vj
	mls.zz += relPos.y*relPos.y*w;		// zz = ∑(yi - yj)^2*Wij*Vj
	mls.zw += relPos.y*relPos.z*w;		// zz = ∑(yi - yj)(zi - zj)*Wij*Vj
	mls.ww += relPos.z*relPos.z*w;		// zz = ∑(yi - yj)^2*Wij*Vj

}

//! MLS contribution
/*!
 contribution of neighbor at relative position relPos with weight w to the
 MLS correction when B is the first row of the inverse MLS matrix
*/
__device__ __forceinline__ float
MlsCorrContrib(float4 const& B, float4 const& relPos, float w)
{
	return (B.x + B.y*relPos.x + B.z*relPos.y + B.w*relPos.z)*w;
	// ρ = ∑(ß0 + ß1(xi - xj) + ß2(yi - yj))*Wij*Vj
}

/*  @} */

/** \name Kernels
 *  @{ */

/************************************************************************************************************/

/************************************************************************************************************/
/*										Density computation							*/
/************************************************************************************************************/

//! Continuity equation with the Grenier formulation
/*!
 When using the Grenier formulation, density is reinitialized at each timestep from
 a Shepard-corrected mass distribution limited to same-fluid particles M and volumes ω computed
 from a continuity equation, with ρ = M/ω.
 During the same run, we also compute σ, the discrete specific volume
 (see e.g. Hu & Adams 2005), obtained by summing the kernel computed over
 _all_ neighbors (not just the same-fluid ones) which is used in the continuity
 equation as well as the Navier-Stokes equation
*/
template<KernelType kerneltype, BoundaryType boundarytype>
__global__ void
densityGrenierDevice(
			float* __restrict__		sigmaArray,
	const	float4* __restrict__	posArray,
			float4* __restrict__	velArray,
	const	particleinfo* __restrict__	infoArray,
	const	hashKey* __restrict__	particleHash,
	const	float4* __restrict__	volArray,
	const	uint* __restrict__		cellStart,
	const	neibdata* __restrict__	neibsList,
	const	uint	numParticles,
	const	float	slength,
	const	float	influenceradius)
{
	const uint index = INTMUL(blockIdx.x,blockDim.x) + threadIdx.x;

	if (index >= numParticles)
		return;

	const particleinfo info = infoArray[index];

	/* We only process FLUID particles normally,
	   except with DYN_BOUNDARY, where we also process boundary particles
	   */
	if (boundarytype != DYN_BOUNDARY && NOT_FLUID(info))
		return;

	const float4 pos = posArray[index];

	if (INACTIVE(pos))
		return;

	const ushort fnum = fluid_num(info);
	const float vol = volArray[index].w;
	float4 vel = velArray[index];

	// self contribution
	float corr = W<kerneltype>(0, slength);
	float sigma = corr;
	float mass_corr = pos.w*corr;

	const int3 gridPos = calcGridPosFromParticleHash( particleHash[index] );

	// For DYN_BOUNDARY particles, we compute sigma in the same way as fluid particles,
	// except that if the boundary particle has no fluid neighbors we set its
	// sigma to a default value which is the 'typical' specific volume, given by
	// the typical number of neighbors divided by the volume of the influence sphere
	bool has_fluid_neibs = false;

	// Loop over all FLUID neighbors, and over BOUNDARY neighbors if using
	// DYN_BOUNDARY
	// TODO: check with SA
	for_each_neib2(PT_FLUID, (boundarytype == DYN_BOUNDARY ? PT_BOUNDARY : PT_NONE),
			index, pos, gridPos, cellStart, neibsList) {

		const uint neib_index = neib_iter.neib_index();

		// Compute relative position vector and distance
		// Now relPos is a float4 and neib mass is stored in relPos.w
		const float4 relPos = neib_iter.relPos(
		#if PREFER_L1
			posArray[neib_index]
		#else
			tex1Dfetch(posTex, neib_index)
		#endif
			);

		const particleinfo neib_info = infoArray[neib_index];
		float r = length(as_float3(relPos));

		/* Contributions only come from active particles within the influence radius
		   that are fluid particles (or also non-fluid in DYN_BOUNDARY case).
		   Sigma calculations uses all such particles, whereas smoothed mass
		   only uses same-fluid particles.
		   Note that this requires PT_BOUNDARY neighbors to be in the list for
		   PT_BOUNDARY particles, lest the boundary particles end up assuming
		   they are always on the free surface.
		   TODO an alternative approach for DYN_BOUNDARY would be to assign
		   the sigma from the closest fluid particle, but that would require
		   two runs, one for fluid and one for neighbor particles.
		 */
		if (INACTIVE(relPos) || r >= influenceradius)
			continue;

		const float w = W<kerneltype>(r, slength);
		sigma += w;
		if (FLUID(neib_info))
			has_fluid_neibs = true;

		/* For smoothed mass, fluid particles only consider fluid particles,
		   and non-fluid (only present for DYN_BOUNDARY) only consider non-fluid
		   */
		if ((boundarytype != DYN_BOUNDARY || (PART_TYPE(neib_info) == PART_TYPE(info)))
			&& fluid_num(neib_info) == fnum) {
			mass_corr += relPos.w*w;
			corr += w;
		}
	}

	if (boundarytype == DYN_BOUNDARY && NOT_FLUID(info) && !has_fluid_neibs) {
		// TODO OPTIMIZE
		const float typical_sigma = 3*(cuneibs::d_maxFluidBoundaryNeibs)/
			(4*M_PIf*influenceradius*influenceradius*influenceradius);
		sigma = typical_sigma;
	}

	// M = mass_corr/corr, ρ = M/ω
	// this could be optimized to pos.w/vol assuming all same-fluid particles
	// have the same mass
	vel.w = mass_corr/(corr*vol);
	vel.w = numerical_density(vel.w,fnum);
	velArray[index] = vel;
	sigmaArray[index] = sigma;
}

/************************************************************************************************************/


/************************************************************************************************************/
/*					   Kernels for computing acceleration without gradient correction					 */
/************************************************************************************************************/

/* forcesDevice kernel and auxiliary types and functions */
#include "forces_kernel.def"

/************************************************************************************************************/


/************************************************************************************************************/
/*					   Kernels for XSPH, Shepard and MLS corrections									   */
/************************************************************************************************************/

//! This kernel computes the Sheppard correction
template<KernelType kerneltype,
	BoundaryType boundarytype>
__global__ void
__launch_bounds__(BLOCK_SIZE_SHEPARD, MIN_BLOCKS_SHEPARD)
shepardDevice(	const float4*	posArray,
				float4*			newVel,
				const hashKey*		particleHash,
				const uint*		cellStart,
				const neibdata*	neibsList,
				const uint		numParticles,
				const float		slength,
				const float		influenceradius)
{
	const uint index = INTMUL(blockIdx.x,blockDim.x) + threadIdx.x;

	if (index >= numParticles)
		return;

	const particleinfo info = tex1Dfetch(infoTex, index);

	#if PREFER_L1
	const float4 pos = posArray[index];
	#else
	const float4 pos = tex1Dfetch(posTex, index);
	#endif

	// If particle is inactive there is absolutely nothing to do
	if (INACTIVE(pos))
		return;

	float4 vel = tex1Dfetch(velTex, index);

	// We apply Shepard normalization :
	//	* with LJ or DYN boundary only on fluid particles
	//TODO 	* with SA boundary ???
	// in any other case we have to copy the vel vector in the new velocity array
	if (NOT_FLUID(info)) {
		newVel[index] = vel;
		return;
	}


	// Taking into account self contribution in summation
	float temp1 = pos.w*W<kerneltype>(0, slength);
	float temp2 = temp1/physical_density(vel.w,fluid_num(info)) ;

	// Compute grid position of current particle
	const int3 gridPos = calcGridPosFromParticleHash( particleHash[index] );

	// Loop over all FLUID neighbors, and over BOUNDARY neighbors if using
	// DYN_BOUNDARY
	// TODO: check with SA
	for_each_neib2(PT_FLUID, (boundarytype == DYN_BOUNDARY ? PT_BOUNDARY : PT_NONE),
			index, pos, gridPos, cellStart, neibsList) {

		const uint neib_index = neib_iter.neib_index();

		// Compute relative position vector and distance
		// Now relPos is a float4 and neib mass is stored in relPos.w
		const float4 relPos = neib_iter.relPos(
		#if PREFER_L1
			posArray[neib_index]
		#else
			tex1Dfetch(posTex, neib_index)
		#endif
			);

		const particleinfo neib_info = tex1Dfetch(infoTex, neib_index);

		// Skip inactive neighbors
		if (INACTIVE(relPos))
			continue;

		const float r = length(as_float3(relPos));

		const float neib_rho = physical_density(tex1Dfetch(velTex, neib_index).w,fluid_num(neib_info));

		if (r < influenceradius ) {
			const float w = W<kerneltype>(r, slength)*relPos.w;
			temp1 += w;
			temp2 += w/neib_rho;
		}
	}

	// Normalize the density and write in global memory
	vel.w = numerical_density(temp1/temp2,fluid_num(info));
	newVel[index] = vel;
}

//! This kernel computes the MLS correction
template<KernelType kerneltype,
	BoundaryType boundarytype>
__global__ void
__launch_bounds__(BLOCK_SIZE_MLS, MIN_BLOCKS_MLS)
MlsDevice(	const float4*	posArray,
			float4*			newVel,
			const hashKey*		particleHash,
			const uint*		cellStart,
			const neibdata*	neibsList,
			const uint		numParticles,
			const float		slength,
			const float		influenceradius)
{
	const uint index = INTMUL(blockIdx.x,blockDim.x) + threadIdx.x;

	if (index >= numParticles)
		return;

	const particleinfo info = tex1Dfetch(infoTex, index);

	#if PREFER_L1
	const float4 pos = posArray[index];
	#else
	const float4 pos = tex1Dfetch(posTex, index);
	#endif

	// If particle is inactive there is absolutely nothing to do
	if (INACTIVE(pos))
		return;

	float4 vel = tex1Dfetch(velTex, index);

	// We apply MLS normalization :
	//	* with LJ or DYN boundary only on fluid particles
	//TODO 	* with SA boundary ???
	// in any other case we have to copy the vel vector in the new velocity array
	//if (NOT_FLUID(info)) {
	//	newVel[index] = vel;
	//	return;
	//}

	// MLS matrix elements
	symtensor4 mls;
	mls.xx = mls.xy = mls.xz = mls.xw =
		mls.yy = mls.yz = mls.yw =
		mls.zz = mls.zw = mls.ww = 0;

	// Number of neighbors
	int neibs_num = 0;

	// Taking into account self contribution in MLS matrix construction
	mls.xx = W<kerneltype>(0, slength)*pos.w/physical_density(vel.w,fluid_num(info));

	// Compute grid position of current particle
	const int3 gridPos = calcGridPosFromParticleHash( particleHash[index] );

	// First loop over neighbors
	// Loop over all FLUID neighbors, and over BOUNDARY neighbors if using
	// DYN_BOUNDARY
	// TODO: check with SA
	for_each_neib2(PT_FLUID, (boundarytype == DYN_BOUNDARY ? PT_BOUNDARY : PT_NONE),
			index, pos, gridPos, cellStart, neibsList) {

		const uint neib_index = neib_iter.neib_index();

		// Compute relative position vector and distance
		// Now relPos is a float4 and neib mass is stored in relPos.w
		const float4 relPos = neib_iter.relPos(
		#if PREFER_L1
			posArray[neib_index]
		#else
			tex1Dfetch(posTex, neib_index)
		#endif
			);

		// Skip inactive particles
		if (INACTIVE(relPos))
			continue;

		const float r = length(as_float3(relPos));
		const particleinfo neib_info = tex1Dfetch(infoTex, neib_index);
		const float neib_rho = physical_density(tex1Dfetch(velTex, neib_index).w,fluid_num(neib_info));
 

		// Add neib contribution only if it's a fluid one
		if (r < influenceradius) {
			neibs_num ++;
			const float w = W<kerneltype>(r, slength)*relPos.w/neib_rho;	// Wij*Vj

			/* Scale relPos by slength for stability and resolution independence */
			MlsMatrixContrib(mls, relPos/slength, w);
		}
	} // end of first loop trough neighbors

	// We want to compute B solution of M B = E where E =(1, 0, 0, 0) and
	// M is our MLS matrix. M is symmetric, positive (semi)definite. Since we
	// cannot guarantee that the matrix is invertible (it won't be in cases
	// such as thin sheets of particles or structures of even lower topological
	// dimension), we rely on the iterative conjugate residual method to
	// find a solution, with E itself as initial guess.

	// known term
	const float4 E = make_float4(1, 0, 0, 0);

	const float D = det(mls);

	// solution
	float4 B;
	if (fabsf(D) < FLT_EPSILON) {
		symtensor4 mls_eps = mls;
		const float eps = fabsf(D) + FLT_EPSILON;
		mls_eps.xx += eps;
		mls_eps.yy += eps;
		mls_eps.zz += eps;
		mls_eps.ww += eps;
		const float D_eps = det(mls_eps);
		B = adjugate_row1(mls_eps)/D_eps;
	} else {
		B = adjugate_row1(mls)/D;
	}

#define MAX_CR_STEPS 32
	uint steps = 0;
	for (; steps < MAX_CR_STEPS; ++steps) {
		float lenB = hypot(B);

		float4 MdotB = dot(mls, B);
		float4 residual = E - MdotB;

		// r.M.r
		float num = ddot(mls, residual);

		// (M.r).(M.r)
		float4 Mp = dot(mls, residual);
		float den = dot(Mp, Mp);

		float4 corr = (num/den)*residual;
		float lencorr = hypot(corr);

		if (hypot(residual) < lenB*FLT_EPSILON)
			break;

		if (lencorr < 2*lenB*FLT_EPSILON)
			break;

		B += corr;
	}

	/* Scale for resolution independence, again */
	B.y /= slength;
	B.z /= slength;
	B.w /= slength;

	// Taking into account self contribution in density summation
	vel.w = B.x*W<kerneltype>(0, slength)*pos.w;

	// Second loop over neighbors
	// Loop over all FLUID neighbors, and over BOUNDARY neighbors if using
	// DYN_BOUNDARY
	// TODO: check with SA
	for_each_neib2(PT_FLUID, (boundarytype == DYN_BOUNDARY ? PT_BOUNDARY : PT_NONE),
			index, pos, gridPos, cellStart, neibsList) {

		const uint neib_index = neib_iter.neib_index();

		// Compute relative position vector and distance
		// Now relPos is a float4 and neib mass is stored in relPos.w
		const float4 relPos = neib_iter.relPos(
		#if PREFER_L1
			posArray[neib_index]
		#else
			tex1Dfetch(posTex, neib_index)
		#endif
			);

		// Skip inactive particles
		if (INACTIVE(relPos))
			continue;

		const float r = length(as_float3(relPos));

		const particleinfo neib_info = tex1Dfetch(infoTex, neib_index);

		// Interaction between two particles
		if (r < influenceradius && (boundarytype == DYN_BOUNDARY || FLUID(neib_info))) {
			const float w = W<kerneltype>(r, slength)*relPos.w;	 // ρj*Wij*Vj = mj*Wij
			vel.w += MlsCorrContrib(B, relPos, w);
		}


	}  // end of second loop trough neighbors

	// If MLS starts misbehaving, define DEBUG_PARTICLE: this will
	// print the MLS-corrected density for the particles statisfying
	// the DEBUG_PARTICLE condition. Some examples:

//#define DEBUG_PARTICLE (index == numParticles - 1)
//#define DEBUG_PARTICLE (id(info) == numParticles - 1)
//#define DEBUG_PARTICLE (fabs(err) > 64*FLT_EPSILON)

#ifdef DEBUG_PARTICLE
	{
		const float old = tex1Dfetch(velTex, index).w;
		const float err = 1 - vel.w/old;
		if (DEBUG_PARTICLE) {
			printf("MLS %d %d %22.16g => %22.16g (%6.2e)\n",
				index, id(info),
				old, vel.w, err*100);
		}
	}
#endif
        vel.w = numerical_density(vel.w,fluid_num(info));
	newVel[index] = vel;
}
/************************************************************************************************************/

/************************************************************************************************************/
/*					   CFL max kernel																		*/
/************************************************************************************************************/
//! Computes the max of an array of floats
/** 
 * Each thread reads 4 elements at a time, computing the max of these four elements (hence why
 * the input type is float4 and not float).
 * The launch grid “slides” over the entire input array, which is compused by numquarts float4s.
 * Each block reduces the per-thread reductions in shared memory, and then writes out a single float.
 */
template <unsigned int blockSize>
__global__ void
fmaxDevice(
	float * __restrict__ output, //< output array,
	const float4 * __restrict__ input, //< input array
	const uint numquarts)
{
	__shared__ float sdata[blockSize];

	/* Step #1: reduction from global memory into a private register */

	// Size of the sliding window
	const unsigned int stride = blockSize*gridDim.x;

	unsigned int i = blockIdx.x*blockSize + threadIdx.x;

	// Accumulator
	float myMax = 0;

	// we reduce multiple elements per thread.  The number is determined by the
	// number of active thread blocks (via gridDim).  More blocks will result
	// in a larger gridSize and therefore fewer elements per thread
	while (i < numquarts)
	{
		float4 in = input[i];
		myMax = fmaxf(myMax, fmaxf(
				fmaxf(in.x, in.y),
				fmaxf(in.z, in.w)));
		i += stride;
	}

	// each thread puts its local sum into shared memory
	const unsigned int tid = threadIdx.x;

	sdata[tid] = myMax;
	__syncthreads();

	// do reduction in shared mem
	if (blockSize >= 512) { if (tid < 256) { sdata[tid] = myMax = fmaxf(myMax,sdata[tid + 256]); } __syncthreads(); }
	if (blockSize >= 256) { if (tid < 128) { sdata[tid] = myMax = fmaxf(myMax,sdata[tid + 128]); } __syncthreads(); }
	if (blockSize >= 128) { if (tid <  64) { sdata[tid] = myMax = fmaxf(myMax,sdata[tid +  64]); } __syncthreads(); }

	// now that we are using warp-synchronous programming (below)
	// we need to declare our shared memory volatile so that the compiler
	// doesn't reorder stores to it and induce incorrect behavior.
	if (tid < 32)
	{
		volatile float* smem = sdata;
		if (blockSize >=  64) { smem[tid] = myMax = fmaxf(myMax, smem[tid + 32]); }
		if (blockSize >=  32) { smem[tid] = myMax = fmaxf(myMax, smem[tid + 16]); }
		if (blockSize >=  16) { smem[tid] = myMax = fmaxf(myMax, smem[tid +  8]); }
		if (blockSize >=   8) { smem[tid] = myMax = fmaxf(myMax, smem[tid +  4]); }
		if (blockSize >=   4) { smem[tid] = myMax = fmaxf(myMax, smem[tid +  2]); }
		if (blockSize >=   2) { smem[tid] = myMax = fmaxf(myMax, smem[tid +  1]); }
	}

	// write result for this block to global mem
	if (tid == 0)
		output[blockIdx.x] = myMax;
}
/************************************************************************************************************/

/** @} */

/************************************************************************************************************/

} //namespace cuforces
#endif
