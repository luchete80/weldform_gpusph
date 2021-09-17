/*  Copyright (c) 2019 INGV, EDF, UniCT, JHU

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
 * Predictor/corrector integrator
 */

#include "Integrator.h"

#include "simframework.h"

class PredictorCorrector : public Integrator
{
	// Phases implemented in this integrator, will be used as index
	// in the m_phase list
	enum PhaseCode {
		POST_UPLOAD, // post-upload phase

		NEIBS_LIST, // neibs list construction phase

		INITIALIZATION, // initialization phase, after upload and neibs list, but before the main integrator loop
		INIT_EFFPRES_PREP, // preparation of effective pressure calculation after INITIALIZATION
		INIT_EFFPRES, // phase in which effective pressure is calculated after INITIALIZATION

		BEGIN_TIME_STEP, // integrator step initialization phase
		PREDICTOR, // predictor phase
		PREDICTOR_END, // end of predictor, prepare for corrector
		POSTPRED_EFFPRES_PREP, // preparation effective pressure calculation after PREDICTOR
		POSTPRED_EFFPRES, // phase in which effective pressure is calculated after PREDICTOR
		CORRECTOR, // corrector phase
		CORRECTOR_END, // end of corrector, prepare for predictor
		POSTCORR_EFFPRES_PREP, // preparation of effective pressure calculation after CORRECTOR
		POSTCORR_EFFPRES, // phase in which effective pressure is calculated after CORRECTOR

		FILTER_INTRO, // prepare to run filters
		FILTER_CALL, // call a single filter
		FILTER_OUTRO, // finish running filters

		NUM_PHASES, // number of phases
	};

	bool m_entered_main_cycle;

	FilterFreqList const& m_enabled_filters;
	FilterFreqList::const_iterator m_current_filter;

	static std::string getCurrentStateForStep(int step_num);
	static std::string getNextStateForStep(int step_num);

	// A function that returns the appropriate time-step operator
	// for the given step number (0 for init, dt/2 for predictor, dt for corrector)
	dt_operator_t getDtOperatorForStep(int step_num);

	// initialize the command sequence for boundary models (one per boundary)
	template<BoundaryType boundarytype>
	void initializeBoundaryConditionsSequence(Phase *this_phase, StepInfo const& step);

	Phase* initializeNextStepSequence(StepInfo const& step_num);
	Phase* initializePredCorrSequence(StepInfo const& step_num);
	Phase* initializeEffPresSolverPrepSequence(StepInfo const& step_num);
	Phase* initializeEffPresSolverSequence(StepInfo const& step_num);

	template<PhaseCode phase>
	void initializePhase();

	// Determine the phase following phase cur
	PhaseCode phase_after(PhaseCode cur);

public:
	// From the generic Integrator we only reimplement
	// the constructor, that will initialize the integrator phases
	PredictorCorrector(GlobalData const* _gdata);

	void start() override
	{ enter_phase(POST_UPLOAD); }

	Phase *next_phase() override;

	FilterType current_filter() const
	{ return m_current_filter->first; }
};
