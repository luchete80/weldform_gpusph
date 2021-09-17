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
 * Commands that GPUSPH can issue to workers via dispatchCommand() calls
 */

#ifndef COMMAND_TYPE_H
#define COMMAND_TYPE_H

#include <string>
#include <vector>

#include "command_flags.h"
#include "common_types.h"
#include "define_buffers.h"

class BufferList;
class ParticleSystem;

//! Next step for workers.
/*! The commands are grouped by category, depending on whether they reflect
 * actual parts of the integrator from those that have a purely “administrative”
 * scope (buffer management etc).
 */
enum CommandName
{
#define DEFINE_COMMAND(code, ...) code,
#include "define_commands.h"
#undef DEFINE_COMMAND
};

//! Array of command names
/*! Maps a CommandName to its string representation.
 * The actual array is defined in src/command_type.cc
 */
extern const char* command_name[];

//! Map CommandName to its C string representation
/*! With proper fencing for undefined commands
 */
inline const char * getCommandName(CommandName cmd)
{
	if (cmd < NUM_COMMANDS)
		return command_name[cmd];
	return "<undefined command>";
}

/*
 * Command traits
 */

//! Specification of buffer usage by commands
enum CommandBufferUsage
{
	NO_BUFFER_USAGE, ///< command does not touch any buffer
	STATIC_BUFFER_USAGE, ///< command works on a fixed set of buffers
	DYNAMIC_BUFFER_USAGE ///< command needs a parameter specifying the buffers to operate on
};

template<CommandName T>
struct CommandTraits
{
	static constexpr CommandName command = T;
	static constexpr CommandBufferUsage buffer_usage = NO_BUFFER_USAGE;
	static constexpr bool only_internal = true;
};


/* Generic macro for the definition of a command traits structure */
/* TODO reads, updates and writes specifications will be moved to the integrator */
#define DEFINE_COMMAND(_command, _internal, _usage) \
template<> \
struct CommandTraits<_command> \
{ \
	static constexpr CommandName command = _command; \
	static constexpr CommandBufferUsage buffer_usage = _usage; \
	static constexpr bool only_internal = _internal; \
};

#include "define_commands.h"

#undef DEFINE_COMMAND

inline bool isCommandInternal(CommandName cmd)
{
	switch (cmd) {
#define DEFINE_COMMAND(_command, _internal, _usage) \
	case _command: return _internal;
#include "define_commands.h"
#undef DEFINE_COMMAND
	default:
		return false;
	}
}

/*
 * Structures needed to specify command arguments
 */

//! A struct specifying buffers within a state
struct StateBuffers
{
	std::string state;
	flag_t buffers;

	StateBuffers(std::string const& state_, flag_t buffers_) :
		state(state_),
		buffers(buffers_)
	{}
};

//! A command buffer usage specification
/*! This is used to specify which buffers, from which states,
 * the command will read, update or write
 */
typedef std::vector<StateBuffers> CommandBufferArgument;

//! Extract the BufferList corresponding to a given state and buffer specification
/*! All buffers are required to exist and be valid
 */
const BufferList extractExistingBufferList(
	ParticleSystem const& ps,
	std::string const& state, const flag_t buffers);

//! Extract the BufferList corresponding to a given StateBuffer
/*! All buffers are required to exist and be valid
 */
const BufferList extractExistingBufferList(
	ParticleSystem const& ps,
	StateBuffers const& arg);
//! Extract the BufferList corresponding to a given CommandBufferArgument
/*! All buffers are required to exist and be valid
 */
const BufferList extractExistingBufferList(
	ParticleSystem const& ps,
	CommandBufferArgument const& arg);
//! Extract the BufferList corresponding to a given CommandBufferArgument
/*! No check is done on the existence and validity of the buffers
 */
BufferList extractGeneralBufferList(
	ParticleSystem& ps,
	CommandBufferArgument const& arg);
//! Extract a buffer list with dynamic buffer specification
/*! This is a version of extractGeneralBufferList that will map
 * BUFFER_NONE specifications to “list of buffers present in the other list”
 */
BufferList extractGeneralBufferList(
	ParticleSystem& ps,
	CommandBufferArgument const& arg,
	BufferList const& model);

struct GlobalData;

//! The type of the methods we use to determine the time-step to use for a command
/** This is just a function that returns a float
 */
typedef float (*dt_operator_t)(GlobalData const*);

//! The default dt operator, that returns NAN
/** Defined in src/command_type.cc
 */
float undefined_dt(GlobalData const*);

//! Information about the integrator step this command belongs to
/*! This structure includes information such as the step number,
 * whether this is the last step or not, etc.
 */
struct StepInfo
{
	//! Step number
	/*! Conventionally, -1 is used to mean 'undetermined',
	 * 0 to indicate the initialization (before entering the main loop)
	 * and sequential numbers from 1 onwards indicate different steps
	 * in the integration (e.g. predictor, corrector)
	 */
	int number;

	bool last; ///< is this the last step?

	StepInfo(int n = -1) :
		number(n),
		last(false)
	{}

	operator int() const
	{ return number; }
};

//! A full command structure
/*! The distinction between updates and writes specification
 * is that in the updates case the buffer(s) will also be read,
 * and must therefore already be present in the corresponding states,
 * whereas writes are considered ignoring previous content, and
 * can therefore be missing/invalid in the state.
 *
 * If the command applies to a single state, src should be set.
 */
struct CommandStruct
{
	CommandName command; ///< the command
	StepInfo step; ///< the step this command belongs to
	std::string src; ///< source state (if applicable)
	std::string dst; ///< destination state (if applicable)
	dt_operator_t dt; ///< function to determine the current time-step
	flag_t flags; ///< command flag (e.g. integration step, shared flags, etc)
	CommandBufferArgument reads;
	CommandBufferArgument updates;
	CommandBufferArgument writes;
	bool only_internal; ///< does the command run only on internal particles?

	CommandStruct(CommandName cmd) :
		command(cmd),
		step(),
		src(),
		dst(),
		dt(undefined_dt),
		flags(NO_FLAGS),
		reads(),
		updates(),
		writes(),
		only_internal(isCommandInternal(cmd))
	{}

	// setters

	CommandStruct& set_step(StepInfo const& step_)
	{ step = step_ ; return *this; }

	CommandStruct& set_src(std::string const& src_)
	{ src = src_; return *this; }
	CommandStruct& set_dst(std::string const& dst_)
	{ dst = dst_; return *this; }

	CommandStruct& set_dt(dt_operator_t func)
	{ dt = func; return *this; }

	CommandStruct& set_flags(flag_t f)
	{ flags |= f; return *this; }
	CommandStruct& clear_flags(flag_t f)
	{ flags &= ~f; return *this; }

	CommandStruct& reading(std::string const& state, flag_t buffers)
	{ reads.push_back(StateBuffers(state, buffers)); return *this; }

	CommandStruct& updating(std::string const& state, flag_t buffers)
	{ updates.push_back(StateBuffers(state, buffers)); return *this; }

	CommandStruct& writing(std::string const& state, flag_t buffers)
	{ writes.push_back(StateBuffers(state, buffers)); return *this; }
};

inline const char * getCommandName(CommandStruct const& cmd)
{ return getCommandName(cmd.command); }


#endif
