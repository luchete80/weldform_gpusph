/*! \file
 * AUTOGENERATED FILE, DO NOT EDIT, see src/debugflags.def instead.
 * A cascade of ifs to parse the debug flags passed on the command line.
 */

if (flag == "print_step") ret.print_step = 1; else 
if (flag == "neibs") ret.neibs = 1; else 
if (flag == "forces") ret.forces = 1; else 
if (flag == "numerical_density") ret.numerical_density = 1; else 
if (flag == "inspect_preforce") ret.inspect_preforce = 1; else 
if (flag == "inspect_pregamma") ret.inspect_pregamma = 1; else 
if (flag == "inspect_buffer_access") ret.inspect_buffer_access = 1; else 
if (flag == "inspect_buffer_lists") ret.inspect_buffer_lists = 1; else 
if (flag == "check_buffer_update") ret.check_buffer_update = 1; else 
if (flag == "check_buffer_consistency") ret.check_buffer_consistency = 1; else 
if (flag == "clobber_invalid_buffers") ret.clobber_invalid_buffers = 1; else 
if (flag == "validate_init_positions") ret.validate_init_positions = 1; else 
if (flag == "benchmark_command_runtimes") ret.benchmark_command_runtimes = 1; else 
