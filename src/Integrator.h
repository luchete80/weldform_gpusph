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
 * Interface for the integrator
 */

#ifndef INTEGRATOR_H
#define INTEGRATOR_H

#include <memory> // shared_ptr
#include "command_type.h"

enum IntegratorType
{
	REPACKING_INTEGRATOR, ///< Integrator that implements the repacking algorithm
	PREDITOR_CORRECTOR ///< Standard GPUSPH predictor/corrector integration scheme
};

struct GlobalData;

class Integrator;

//! A sequence of commands, modelling a phase of the integrator
/*! This is essentially an std::vector<CommandStruct>, with minor changes:
 * it only exposes reserve(), constant begin() and end() methods, and
 * a push_back() method that returns a reference to back()
 */
class CommandSequence
{
	using base = std::vector<CommandStruct>;
	using size_type = base::size_type;
	base m_seq;

	friend class Integrator;

protected:
	CommandStruct& at(size_type pos)
	{ return m_seq.at(pos); }

public:
	CommandSequence() : m_seq() {}

	void reserve(size_t sz)
	{ m_seq.reserve(sz); }

	base::const_iterator begin() const
	{ return m_seq.begin(); }
	base::const_iterator end() const
	{ return m_seq.end(); }

	size_type size() const
	{ return m_seq.size(); }

	// is this command sequence empty?
	bool empty() const
	{ return m_seq.empty(); }

	const CommandStruct& at(size_type pos) const
	{ return m_seq.at(pos); }

	CommandStruct& push_back(CommandStruct const& cmd)
	{
		m_seq.push_back(cmd);
		return m_seq.back();
	}
};

/*! An integrator is a sequence of phases, where each phase is a sequence of commands.
 * Phases can be both simple (once the sequence of commands is over, we move on to the next phase)
 * and iterative (e.g. in implicit or semi-implicit schemes, the sequence of commands needed for
 * implicit solving are repeated until a specific condition is met.
 * Most integrators share at least the phases for the neighbors list construction, filtering,
 * post-processing and some transitions.
 */

class Integrator
{
public:
	class Phase
	{
		Integrator const* m_owner; ///< Integrator owning this phase
		std::string m_name; ///< name of this phase
		CommandSequence m_command; ///< sequence of commands to execute for this phase
		size_t m_cmd_idx; ///< current command

		///< type of the functions that determine if a phase should run
		typedef bool (*should_run_t)(Phase const*, GlobalData const*);

		///< type of the functions that determine if a phase is done
		/* Currently this is the same as should_run_t */
		using is_done_t = should_run_t;

		///< type of the functions called on reset()
		typedef void (*reset_t)(Phase*, Integrator const*);

		///< the function that determines if this phase should run
		should_run_t m_should_run;

		///< the function that determines if this phase is done
		is_done_t m_is_done;

		///< the function called on reset
		reset_t m_reset_func;

		/* The next commands should actually be only accessible to Integrator and its
		 * derived class, but there is no way to achieve that. We probably should look into
		 * providing a different interface
		 */
	public:
		void reserve(size_t num_cmds)
		{ return m_command.reserve(num_cmds); }

		CommandStruct& add_command(CommandName cmd)
		{ return m_command.push_back(cmd); }

		CommandStruct& edit_command(size_t idx)
		{ return m_command.at(idx); }

		// Reset the phase on enter.
		void reset_index()
		{ m_cmd_idx = 0; }

		void reset()
		{ m_reset_func(this, m_owner); }

		//! Change the condition under which the phase should run
		void should_run_if(should_run_t new_should_run_cond)
		{ m_should_run = new_should_run_cond; }

		//! Change the condition under which the phase is done
		void is_done_if(is_done_t new_is_done_cond)
		{ m_is_done = new_is_done_cond; }

		//! Change the reset function
		void set_reset_function(reset_t reset_func)
		{ m_reset_func = reset_func; }

	public:

		// is this phase empty?
		bool empty() const
		{ return m_command.empty(); }

		// is this phase not empty?
		bool not_empty() const
		{ return !empty(); }

		// has this phase run all commands?
		bool finished_commands() const
		{ return m_cmd_idx == m_command.size(); }

		bool should_run(GlobalData const* gdata) const
		{ return m_should_run(this, gdata); }

		// Is this phase done?
		bool done(GlobalData const* gdata) const
		{ return m_is_done(this, gdata); }

		// by default the phase runs if it's not empty
		static bool default_should_run(Phase const* p, GlobalData const*)
		{ return p->not_empty(); }

		// by default the phase is done if it has finished the commands
		// iterative phases may restart under appropriate conditions
		// or bail out early
		static bool default_is_done(Phase const* p, GlobalData const*)
		{ return p->finished_commands(); }

		// by default the reset simply resets the index to the default
		static void default_reset(Phase *p, Integrator const*)
		{ p->reset_index(); }

		Phase(Integrator const* owner, std::string && name) :
			m_owner(owner),
			m_name(name),
			m_command(),
			m_cmd_idx(0),
			m_should_run(default_should_run),
			m_is_done(default_is_done),
			m_reset_func(default_reset)
		{}

		std::string const& name() const
		{ return m_name; }

		CommandStruct const* current_command() const
		{ return &m_command.at(m_cmd_idx); }

		CommandStruct const* next_command()
		{
			CommandStruct const* cmd = current_command();
			++m_cmd_idx;
			return cmd;
		}


	};

protected:
	GlobalData const* gdata;

	std::string m_name; ///< name of the integrator
	std::vector<Phase *> m_phase; ///< phases of the integrator
	size_t m_phase_idx; ///< current phase

public:

	// the Integrator name
	std::string const& name() const
	{ return m_name; }

	// a pointer to the current integrator phase
	Phase const* current_phase() const
	{ return m_phase.at(m_phase_idx); }

protected:
	// a pointer to the current integrator phase
	Phase* current_phase()
	{ return m_phase.at(m_phase_idx); }

	Phase* enter_phase(size_t phase_idx);

	//! Move on to the next phase
	//! Derived classes should override this to properly implement
	//! transition to different phases
	virtual Phase* next_phase()
	{ return enter_phase(m_phase_idx + 1); }

	//! Define the standard neighbors list construction phase.
	/*! The buffers to be sorted, and then imported across devices, is passed
	 *  by the calling integrator (aside from PARTICLE_SUPPORT_BUFFERs which are
	 *  always included).
	 *  It's also up to the individual integratos to put this sequence of steps
	 *  in the correct place of the sequence
	 */
	Phase * buildNeibsPhase(flag_t import_buffers);

	// TODO we should move here phase generators that are common between (most)
	// integrators

public:

	// Instance the integrator defined by the given IntegratorType, constructing it
	// from the given gdata
	static
	std::shared_ptr<Integrator> instance(IntegratorType, GlobalData const* _gdata);

	Integrator(GlobalData const* _gdata, std::string && name) :
		gdata(_gdata),
		m_name(name),
		m_phase(),
		m_phase_idx(0)
	{}

	virtual ~Integrator()
	{
		for (Phase* phase : m_phase)
			delete phase;
	}

	// Start the integrator
	virtual void start()
	{ enter_phase(0); }

	// Called from GPUSPH to indicate that we are finished.
	// Most integrators will do nothing at this point, but the RepackingIntegrator
	// can use this to get out of the main loop as switch to the end-of-repacking phase
	virtual void we_are_done()
	{ }

	// Fetch the next command
	CommandStruct const* next_command()
	{
		Phase* phase = current_phase();
		if (phase->done(gdata))
			phase = next_phase();
		return phase->next_command();
	}
};

#endif
