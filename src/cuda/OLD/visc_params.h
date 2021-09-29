/*  Copyright (c) 2018-2019 INGV, EDF, UniCT, JHU

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

/*! \file
 * Parameter structures for the visc kernels
 */

#ifndef _VISC_PARAMS_H
#define _VISC_PARAMS_H

#include "cond_params.h"
#include "neibs_list_params.h"

#include "simflags.h"

/// Parameters passed to the SPS kernel only if simflag SPS_STORE_TAU is set
struct tau_sps_params
{
	float2* __restrict__		tau0;
	float2* __restrict__		tau1;
	float2* __restrict__		tau2;

	tau_sps_params(float2 * __restrict__ _tau0, float2 * __restrict__ _tau1, float2 * __restrict__ _tau2) :
		tau0(_tau0), tau1(_tau1), tau2(_tau2)
	{}
};

/// Parameters passed to the SPS kernel only if simflag SPS_STORE_TURBVISC is set
struct turbvisc_sps_params
{
	float	* __restrict__ turbvisc;
	turbvisc_sps_params(float * __restrict__ _turbvisc) :
		turbvisc(_turbvisc)
	{}
};


/// The actual sps_params struct, which concatenates all of the above, as appropriate.
template<KernelType _kerneltype,
	BoundaryType _boundarytype,
	uint _sps_simflags>
struct sps_params :
	neibs_list_params,
	COND_STRUCT(_sps_simflags & SPSK_STORE_TAU, tau_sps_params),
	COND_STRUCT(_sps_simflags & SPSK_STORE_TURBVISC, turbvisc_sps_params)
{
	static constexpr KernelType kerneltype = _kerneltype;
	static constexpr BoundaryType boundarytype = _boundarytype;
	static const uint sps_simflags = _sps_simflags;

	// This structure provides a constructor that takes as arguments the union of the
	// parameters that would ever be passed to the forces kernel.
	// It then delegates the appropriate subset of arguments to the appropriate
	// structs it derives from, in the correct order
	sps_params(
		// common
			const	float4* __restrict__	_posArray,
			const	hashKey* __restrict__	_particleHash,
			const	uint* __restrict__		_cellStart,
			const	neibdata* __restrict__	_neibsList,
			const	uint		_numParticles,
			const	float		_slength,
			const	float		_influenceradius,
		// tau
					float2* __restrict__		_tau0,
					float2* __restrict__		_tau1,
					float2* __restrict__		_tau2,
		// turbvisc
					float* __restrict__		_turbvisc
		) :
		neibs_list_params(_posArray, _particleHash, _cellStart,
			_neibsList, _numParticles, _slength, _influenceradius),
		COND_STRUCT(sps_simflags & SPSK_STORE_TAU, tau_sps_params)(_tau0, _tau1, _tau2),
		COND_STRUCT(sps_simflags & SPSK_STORE_TURBVISC, turbvisc_sps_params)(_turbvisc)
	{}
};

//! Parameters needed when reducing the kinematic visc to find its maximum value
struct visc_reduce_params
{
	float * __restrict__	cfl;
	visc_reduce_params(float* __restrict__ _cfl) :
		cfl(_cfl)
	{}
};

//! Additional parameters passed only with SA_BOUNDARY
struct sa_boundary_rheology_params
{
	const	float4	* __restrict__ gGam;
	const	float2	* __restrict__ vertPos0;
	const	float2	* __restrict__ vertPos1;
	const	float2	* __restrict__ vertPos2;
	sa_boundary_rheology_params(const float4 * __restrict__ const _gGam, const   float2  * __restrict__  const _vertPos[])
	{
		if (!_gGam) throw std::invalid_argument("no gGam for sa_boundary_visc_params");
		if (!_vertPos) throw std::invalid_argument("no vertPos for sa_boundary_visc_params");
		gGam = _gGam;
		vertPos0 = _vertPos[0];
		vertPos1 = _vertPos[1];
		vertPos2 = _vertPos[2];
	}
};

//! Effective viscosity kernel parameters
/** in addition to the standard neibs_list_params, it only includes
 * the array where the effective viscosity is written
 */
template<KernelType _kerneltype,
	BoundaryType _boundarytype,
	typename _ViscSpec,
	flag_t _simflags,
	typename reduce_params =
		typename COND_STRUCT(_simflags & ENABLE_DTADAPT, visc_reduce_params),
	typename sa_params =
		typename COND_STRUCT(_boundarytype == SA_BOUNDARY, sa_boundary_rheology_params)
	>
struct effvisc_params :
	neibs_list_params,
	reduce_params,
	sa_params
{
	float * __restrict__	effvisc;
	const float 		deltap;

	using ViscSpec = _ViscSpec;

	static constexpr KernelType kerneltype = _kerneltype;
	static constexpr BoundaryType boundarytype = _boundarytype;
	static constexpr RheologyType rheologytype = ViscSpec::rheologytype;
	static constexpr flag_t simflags = _simflags;

	effvisc_params(
		// common
			const	float4* __restrict__	_posArray,
			const	hashKey* __restrict__	_particleHash,
			const	uint* __restrict__		_cellStart,
			const	neibdata* __restrict__	_neibsList,
			const	uint		_numParticles,
			const	float		_slength,
			const	float		_influenceradius,
			const	float		_deltap,
		// SA_BOUNDARY params
			const	float4* __restrict__	_gGam,
			const	float2* const *_vertPos,
		// effective viscosity
					float*	__restrict__	_effvisc,
					float*	__restrict__	_cfl) :
	neibs_list_params(_posArray, _particleHash, _cellStart, _neibsList, _numParticles,
		_slength, _influenceradius),
	deltap(_deltap),
	reduce_params(_cfl),
	sa_params(_gGam, _vertPos),
	effvisc(_effvisc)
	{}
};

//! Effective pressure kernel parameters
/** in addition to the standard neibs_list_params, it only includes
 * the array where the effective pressure is written
 */
template<KernelType _kerneltype,
	BoundaryType _boundarytype,
	typename sa_params =
		typename COND_STRUCT(_boundarytype == SA_BOUNDARY, sa_boundary_rheology_params)
	>
struct effpres_params :
	neibs_list_params,
	visc_reduce_params,
	sa_params
{
	float * __restrict__	effpres;
	const float 		deltap;

	static constexpr KernelType kerneltype = _kerneltype;
	static constexpr BoundaryType boundarytype = _boundarytype;

	effpres_params(
		// common
			const	float4* __restrict__	_posArray,
			const	hashKey* __restrict__	_particleHash,
			const	uint* __restrict__		_cellStart,
			const	neibdata* __restrict__	_neibsList,
			const	uint		_numParticles,
			const	float		_slength,
			const	float		_influenceradius,
			const	float		_deltap,
		// SA_BOUNDARY params
			const	float4* __restrict__	_gGam,
			const	float2* const *_vertPos,
		// effective viscosity
					float*	__restrict__	_effpres,
					float*	__restrict__	_cfl) :
	neibs_list_params(_posArray, _particleHash, _cellStart, _neibsList, _numParticles,
		_slength, _influenceradius),
	deltap(_deltap),
	visc_reduce_params(_cfl),
	sa_params(_gGam, _vertPos),
	effpres(_effpres)
	{}
};


#endif // _VISC_PARAMS_H
