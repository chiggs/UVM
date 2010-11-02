//
//------------------------------------------------------------------------------
//   Copyright 2007-2010 Mentor Graphics Corporation
//   Copyright 2007-2010 Cadence Design Systems, Inc.
//   Copyright 2010 Synopsys, Inc.
//   All Rights Reserved Worldwide
//
//   Licensed under the Apache License, Version 2.0 (the
//   "License"); you may not use this file except in
//   compliance with the License.  You may obtain a copy of
//   the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in
//   writing, software distributed under the License is
//   distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
//   CONDITIONS OF ANY KIND, either express or implied.  See
//   the License for the specific language governing
//   permissions and limitations under the License.
//------------------------------------------------------------------------------

`include "base/uvm_component.svh"
`include "base/uvm_root.svh"

uvm_component uvm_top_levels[$];



//------------------------------------------------------------------------------
//
// CLASS- uvm_component
//
//------------------------------------------------------------------------------


// new
// ---

function uvm_component::new (string name, uvm_component parent);
  string error_str;

  super.new(name);

  // If uvm_top, reset name to "" so it doesn't show in full paths then return
  if (parent==null && name == "__top__") begin
    set_name("");
    return;
  end

  // Check that we're not in or past end_of_elaboration
  begin
    uvm_phase_schedule common, end_of_elab;
    common = uvm_top.find_phase_schedule("uvm_pkg::common","common");
    if (common != null) begin
      // only check if we have got phasing set up yet
      end_of_elab = common.find_schedule("end_of_elaboration");
      if (end_of_elab.get_state == UVM_PHASE_EXECUTING ||
          end_of_elab.get_run_count > 0 ) begin
        uvm_phase_schedule curr_phase;
        curr_phase = uvm_top.get_current_phase();
        uvm_report_fatal("ILLCRT", {"It is illegal to create a component once",
                                    " phasing reaches end_of_elaboration. The current phase is ", 
                                    curr_phase.get_phase_name()}, UVM_NONE);
      end
    end
  end

  if (name == "") begin
    name.itoa(m_inst_count);
    name = {"COMP_", name};
  end

  if(parent == this) begin
    uvm_report_fatal("THISPARENT", "cannot set the parent of a component to itself", UVM_NONE);
  end

  if (parent == null)
    parent = uvm_top;

  if(uvm_report_enabled(UVM_MEDIUM+1, UVM_INFO, "NEWCOMP"))
    uvm_report_info("NEWCOMP",$psprintf("this=%0s, parent=%0s, name=%s",
                    this.get_full_name(),parent.get_full_name(),name),UVM_MEDIUM+1);

  if (parent.has_child(name) && this != parent.get_child(name)) begin
    if (parent == uvm_top) begin
      error_str = {"Name '",name,"' is not unique to other top-level ",
      "instances. If parent is a module, build a unique name by combining the ",
      "the module name and component name: $psprintf(\"\%m.\%s\",\"",name,"\")."};
      uvm_report_fatal("CLDEXT",error_str, UVM_NONE);
    end
    else
      uvm_report_fatal("CLDEXT",
        $psprintf("Cannot set '%s' as a child of '%s', %s",
                  name, parent.get_full_name(),
                  "which already has a child by that name."), UVM_NONE);
    return;
  end

  m_parent = parent;

  set_name(name);

  if (!m_parent.m_add_child(this))
    m_parent = null;

  event_pool = new("event_pool");

  // initialize phase schedule to "common", or inherit it from parent component
  // - domain can be overridden by set_phase_domain()
  // - schedule can be augmented by set_phase_schedule()
  if (parent == uvm_top || parent == null) begin
    uvm_phase_schedule common;
    common = uvm_top.find_phase_schedule("uvm_pkg::common","common");
    if (common == null) begin
      // build phase schedule 'uvm_pkg::common', used by all uvm_component instances
      // - it is a linear list of predefined phases (see uvm_globals.svh) as follows:
      common = new("uvm_pkg::common");
      // note: could not do this in uvm_root::new() due to static initialization ordering
      common.add_phase(uvm_build_ph);
      common.add_phase(uvm_connect_ph);
      common.add_phase(uvm_end_of_elaboration_ph);
      common.add_phase(uvm_start_of_simulation_ph);
      common.add_phase(uvm_run_ph);
      common.add_phase(uvm_extract_ph);
      common.add_phase(uvm_check_ph);
      common.add_phase(uvm_report_ph);
      common.add_phase(uvm_finalize_ph);
      // schedule/domain pair is added to the master list with fixed domain name "common"
      uvm_top.add_phase_schedule(common, "common");
    end
    add_phase_schedule(common, "common");
  end else begin
    foreach(parent.m_phase_domains[schedule])
      m_phase_domains[schedule] = parent.m_phase_domains[schedule];
  end
  
  // Now that inst name is established, reseed (if use_uvm_seeding is set)
  reseed();

  // Do local configuration settings
  void'(get_config_int("recording_detail", recording_detail));

  if (parent == uvm_top)
    uvm_top_levels.push_back(this);

  set_report_verbosity_level(uvm_top.get_report_verbosity_level());

  set_report_id_action("CFGOVR", UVM_NO_ACTION);
  set_report_id_action("CFGSET", UVM_NO_ACTION);

//Not sure what uvm_top isn't taking the setting... these two lines should be removed.
  uvm_top.set_report_id_action("CFGOVR", UVM_NO_ACTION);
  uvm_top.set_report_id_action("CFGSET", UVM_NO_ACTION);
endfunction


// m_add_child
// -----------

function bit uvm_component::m_add_child(uvm_component child);

  if (m_children.exists(child.get_name()) &&
      m_children[child.get_name()] != child) begin
      uvm_report_warning("BDCLD",
        $psprintf("A child with the name '%0s' (type=%0s) already exists.",
           child.get_name(), m_children[child.get_name()].get_type_name()), UVM_NONE);
      return 0;
  end

  if (m_children_by_handle.exists(child)) begin
      uvm_report_warning("BDCHLD",
        $psprintf("A child with the name '%0s' %0s %0s'",
                  child.get_name(),
                  "already exists in parent under name '",
                  m_children_by_handle[child].get_name()), UVM_NONE);
      return 0;
    end

  m_children[child.get_name()] = child;
  m_children_by_handle[child] = child;
  return 1;
endfunction



//------------------------------------------------------------------------------
//
// Hierarchy Methods
// 
//------------------------------------------------------------------------------


// get_first_child
// ---------------

function int uvm_component::get_first_child(ref string name);
  return m_children.first(name);
endfunction


// get_next_child
// --------------

function int uvm_component::get_next_child(ref string name);
  return m_children.next(name);
endfunction


// get_child
// ---------

function uvm_component uvm_component::get_child(string name);
  if (m_children.exists(name))
    return m_children[name];
  uvm_report_warning("NOCHILD",{"Component with name '",name,
       "' is not a child of component '",get_full_name(),"'"}, UVM_NONE); 
  return null;
endfunction


// has_child
// ---------

function int uvm_component::has_child(string name);
  return m_children.exists(name);
endfunction


// get_num_children
// ----------------

function int uvm_component::get_num_children();
  return m_children.num();
endfunction


// get_full_name
// -------------

function string uvm_component::get_full_name ();
  // Note- Implementation choice to construct full name once since the
  // full name may be used often for lookups.
  if(m_name == "")
    return get_name();
  else
    return m_name;
endfunction


// get_parent
// ----------

function uvm_component uvm_component::get_parent ();
  return  m_parent;
endfunction


// set_name
// --------

function void uvm_component::set_name (string name);
  
  super.set_name(name);
  m_set_full_name();

endfunction


// m_set_full_name
// ---------------

function void uvm_component::m_set_full_name();
  if (m_parent == uvm_top || m_parent==null)
    m_name = get_name();
  else 
    m_name = {m_parent.get_full_name(), ".", get_name()};

  foreach (m_children[c]) begin
    uvm_component tmp;
    tmp = m_children[c];
    tmp.m_set_full_name(); 
  end

endfunction


// lookup
// ------

function uvm_component uvm_component::lookup( string name );

  string leaf , remainder;
  uvm_component comp;

  comp = this;
  
  m_extract_name(name, leaf, remainder);

  if (leaf == "") begin
    comp = uvm_top; // absolute lookup
    m_extract_name(remainder, leaf, remainder);
  end
  
  if (!comp.has_child(leaf)) begin
    uvm_report_warning("Lookup Error", 
       $psprintf("Cannot find child %0s",leaf), UVM_NONE);
    return null;
  end

  if( remainder != "" )
    return comp.m_children[leaf].lookup(remainder);

  return comp.m_children[leaf];

endfunction


// m_extract_name
// --------------

function void uvm_component::m_extract_name(input string name ,
                                            output string leaf ,
                                            output string remainder );
  int i , len;
  string extract_str;
  len = name.len();
  
  for( i = 0; i < name.len(); i++ ) begin  
    if( name[i] == "." ) begin
      break;
    end
  end

  if( i == len ) begin
    leaf = name;
    remainder = "";
    return;
  end

  leaf = name.substr( 0 , i - 1 );
  remainder = name.substr( i + 1 , len - 1 );

  return;
endfunction
  

// flush
// -----

function void uvm_component::flush();
  return;
endfunction


// do_flush  (flush_hier?)
// --------

function void uvm_component::do_flush();
  foreach( m_children[s] )
    m_children[s].do_flush();
  flush();
endfunction
  


//------------------------------------------------------------------------------
//
// Factory Methods
// 
//------------------------------------------------------------------------------


// create
// ------

function uvm_object  uvm_component::create (string name =""); 
  uvm_report_error("ILLCRT",
    "create cannot be called on a uvm_component. Use create_component instead.", UVM_NONE);
  return null;
endfunction


// clone
// ------

function uvm_object  uvm_component::clone ();
  uvm_report_error("ILLCLN","clone cannot be called on a uvm_component. ", UVM_NONE);
  return null;
endfunction


// print_override_info
// -------------------

function void  uvm_component::print_override_info (string requested_type_name, 
                                                   string name="");
  factory.debug_create_by_name(requested_type_name, get_full_name(), name);
endfunction


// create_component
// ----------------

function uvm_component uvm_component::create_component (string requested_type_name,
                                                        string name);
  return factory.create_component_by_name(requested_type_name, get_full_name(),
                                          name, this);
endfunction


// create_object
// -------------

function uvm_object uvm_component::create_object (string requested_type_name,
                                                  string name="");
  return factory.create_object_by_name(requested_type_name,
                                       get_full_name(), name);
endfunction


// set_type_override (static)
// -----------------

function void uvm_component::set_type_override (string original_type_name,
                                                string override_type_name,
                                                bit    replace=1);
   factory.set_type_override_by_name(original_type_name,
                                     override_type_name, replace);
endfunction 


// set_type_override_by_type (static)
// -------------------------

function void uvm_component::set_type_override_by_type (uvm_object_wrapper original_type,
                                                        uvm_object_wrapper override_type,
                                                        bit    replace=1);
   factory.set_type_override_by_type(original_type, override_type, replace);
endfunction 


// set_inst_override
// -----------------

function void  uvm_component::set_inst_override (string relative_inst_path,  
                                                 string original_type_name,
                                                 string override_type_name);
  string full_inst_path;

  if (relative_inst_path == "")
    full_inst_path = get_full_name();
  else
    full_inst_path = {get_full_name(), ".", relative_inst_path};

  factory.set_inst_override_by_name(
                            original_type_name,
                            override_type_name,
                            full_inst_path);
endfunction 


// set_inst_override_by_type
// -------------------------

function void uvm_component::set_inst_override_by_type (string relative_inst_path,  
                                                        uvm_object_wrapper original_type,
                                                        uvm_object_wrapper override_type);
  string full_inst_path;

  if (relative_inst_path == "")
    full_inst_path = get_full_name();
  else
    full_inst_path = {get_full_name(), ".", relative_inst_path};

  factory.set_inst_override_by_type(original_type, override_type, full_inst_path);

endfunction



//------------------------------------------------------------------------------
//
// Hierarchical report configuration interface
//
//------------------------------------------------------------------------------


// set_report_severity_action_hier
// -------------------------------

function void uvm_component::set_report_severity_action_hier( uvm_severity severity,
                                                              uvm_action action);
  set_report_severity_action(severity, action);
  foreach( m_children[c] )
    m_children[c].set_report_severity_action_hier(severity, action);
endfunction


// set_report_id_action_hier
// -------------------------

function void uvm_component::set_report_id_action_hier( string id, uvm_action action);
  set_report_id_action(id, action);
  foreach( m_children[c] )
    m_children[c].set_report_id_action_hier(id, action);
endfunction


// set_report_severity_id_action_hier
// ----------------------------------

function void uvm_component::set_report_severity_id_action_hier( uvm_severity severity,
                                                                 string id,
                                                                 uvm_action action);
  set_report_severity_id_action(severity, id, action);
  foreach( m_children[c] )
    m_children[c].set_report_severity_id_action_hier(severity, id, action);
endfunction


// set_report_severity_file_hier
// -----------------------------

function void uvm_component::set_report_severity_file_hier( uvm_severity severity,
                                                            UVM_FILE file);
  set_report_severity_file(severity, file);
  foreach( m_children[c] )
    m_children[c].set_report_severity_file_hier(severity, file);
endfunction


// set_report_default_file_hier
// ----------------------------

function void uvm_component::set_report_default_file_hier( UVM_FILE file);
  set_report_default_file(file);
  foreach( m_children[c] )
    m_children[c].set_report_default_file_hier(file);
endfunction


// set_report_id_file_hier
// -----------------------
  
function void uvm_component::set_report_id_file_hier( string id, UVM_FILE file);
  set_report_id_file(id, file);
  foreach( m_children[c] )
    m_children[c].set_report_id_file_hier(id, file);
endfunction


// set_report_severity_id_file_hier
// --------------------------------

function void uvm_component::set_report_severity_id_file_hier ( uvm_severity severity,
                                                                string id,
                                                                UVM_FILE file);
  set_report_severity_id_file(severity, id, file);
  foreach( m_children[c] )
    m_children[c].set_report_severity_id_file_hier(severity, id, file);
endfunction


// set_report_verbosity_level_hier
// -------------------------------

function void uvm_component::set_report_verbosity_level_hier(int verbosity);
  set_report_verbosity_level(verbosity);
  foreach( m_children[c] )
    m_children[c].set_report_verbosity_level_hier(verbosity);
endfunction  



//------------------------------------------------------------------------------
//
// Phase interface 
//
//------------------------------------------------------------------------------


// phase methods
//--------------
// these are prototypes for the methods to be implemented in user components
// build() has a default implementation, the others have an empty default

function void uvm_component::build();
  apply_config_settings(print_config_matches);
endfunction

// these phase methods are common to all components in UVM

function void uvm_component::connect();             return; endfunction
function void uvm_component::start_of_simulation(); return; endfunction
function void uvm_component::end_of_elaboration();  return; endfunction
task          uvm_component::run();                 return; endtask
function void uvm_component::extract();             return; endfunction
function void uvm_component::check();               return; endfunction
function void uvm_component::report();              return; endfunction
function void uvm_component::finalize();            return; endfunction

// these runtime phase methods are only called if a set_domain() is done

task          uvm_component::pre_reset();           return; endtask
task          uvm_component::reset();               return; endtask
task          uvm_component::post_reset();          return; endtask
task          uvm_component::pre_configure();       return; endtask
task          uvm_component::configure();           return; endtask
task          uvm_component::post_configure();      return; endtask
task          uvm_component::pre_main();            return; endtask
task          uvm_component::main();                return; endtask
task          uvm_component::post_main();           return; endtask
task          uvm_component::pre_shutdown();        return; endtask
task          uvm_component::shutdown();            return; endtask
task          uvm_component::post_shutdown();       return; endtask


// current phase convenience API
//------------------------------


// phase_started() and phase_ended() are extra callbacks called at the
// beginning and end of each phase, respectively.  Since they are
// called for all phases the phase is passed in as an argument so the
// extender can decide what to do, if anything, for each phase.

function void uvm_component::phase_started(uvm_phase_schedule phase);
endfunction


function void uvm_component::phase_ended(uvm_phase_schedule phase);
endfunction


function uvm_phase_schedule uvm_component::get_current_phase();
  foreach (m_phase_threads[phase])
    if (m_phase_threads[phase].is_current_process()) return phase;
  uvm_report_fatal("BADTHREAD", "unable to determine current phase for this process thread");
endfunction


function string uvm_component::find_phase_domain(string schedule_name="uvm_pkg::uvm");
  foreach (m_phase_domains[schedule])
    if (schedule.get_schedule_name() == schedule_name)
      return m_phase_domains[schedule];
  uvm_report_fatal("BADDOMAIN", {"component has no '", schedule_name, "' schedule domain"});
endfunction


function uvm_phase_schedule uvm_component::find_phase_schedule(string name, string domain);
  foreach (m_phase_domains[schedule])
    if (((name == "*") || (schedule.get_schedule_name() == name)) &&
        ((domain == "*") || (m_phase_domains[schedule] == domain)))
      return schedule;
  return null;
endfunction


function void uvm_component::add_phase_schedule(uvm_phase_schedule schedule, string domain);
  m_phase_domains[schedule] = domain;
endfunction


function void uvm_component::delete_phase_schedule(uvm_phase_schedule schedule);
  m_phase_domains.delete(schedule);
endfunction


// phase / schedule / domain API
//------------------------------
// methods for VIP creators and integrators to use to set up schedule domains
// - a schedule is a named, organized group of phases for a component base type
// - a domain is a named instance of a schedule in the master phasing schedule


// here we define the "uvm_pkg::uvm" schedule containing the UVM runtime phases
// - and add a named instance of it to the root schedule [if not already there]
// - and add the schedule handle to this component's domain membership list
// [replacing any existing handles comp has to this schedule in other domains]

// components using these phases must subscribe by calling set_domain(name)

function void uvm_component::set_phase_schedule(string domain_name);
  const string schedule_name = "uvm_pkg::uvm";
  uvm_phase_schedule uvm;

  // find this schedule/domain in the master schedule if it exists
  uvm = uvm_top.find_phase_schedule(schedule_name, domain_name);

  // create it and add it to master schedule if it doesn't exist
  if (uvm == null) begin
    uvm = new(schedule_name);
    // schedule consists of a linear list of predefined phases
    uvm.add_phase(uvm_pre_reset_ph);
    uvm.add_phase(uvm_reset_ph);
    uvm.add_phase(uvm_post_reset_ph);
    uvm.add_phase(uvm_pre_configure_ph);
    uvm.add_phase(uvm_configure_ph);
    uvm.add_phase(uvm_post_configure_ph);
    uvm.add_phase(uvm_pre_main_ph);
    uvm.add_phase(uvm_main_ph);
    uvm.add_phase(uvm_post_main_ph);
    uvm.add_phase(uvm_pre_shutdown_ph);
    uvm.add_phase(uvm_shutdown_ph);
    uvm.add_phase(uvm_post_shutdown_ph);
    // schedule is integrated hierarchically in parallel with the "run" phase
    // of the "uvm_pkg::common" schedule, for the specified domain
    begin
      uvm_phase_schedule common;
      common = uvm_top.find_phase_schedule("uvm_pkg::common","common");
      common.add_schedule(uvm, .with_phase(common.find_schedule("run")));
    end
    // schedule/domain pair is added to the master list
    uvm_top.add_phase_schedule(uvm, domain_name);
  end

  // add schedule to this component's list, replacing any existing entry found
  if (find_phase_schedule(schedule_name,"*"))
    delete_phase_schedule(find_phase_schedule(schedule_name,"*"));
  add_phase_schedule(uvm, domain_name);
endfunction

function void uvm_component::set_phase_domain(string domain_name, int hier=1);
  set_phase_schedule(domain_name);
  if (hier) foreach (m_children[c]) m_children[c].set_phase_domain(domain_name,hier);
endfunction

function void uvm_component::set_phase_imp(uvm_phase_imp phase, uvm_phase_imp imp, int hier=1);
  m_phase_imps[phase] = imp;
  if (hier) foreach (m_children[c]) m_children[c].set_phase_imp(phase,imp,hier);
endfunction


// phase process / thread semantics API
//-------------------------------------

function void uvm_component::set_default_thread_mode(uvm_thread_mode_t thread_mode);
  m_phase_thread_mode = thread_mode;
endfunction

function void uvm_component::set_thread_mode(uvm_thread_mode_t thread_mode);
  foreach (m_phase_threads[phase]) begin
    if (m_phase_threads[phase].is_current_process()) begin
      m_phase_threads[phase].set_thread_mode(thread_mode);
      return;
    end
  end
  //TBD fatal
endfunction


// phase runtime control API
// -------------------------

function void uvm_component::jump(uvm_phase_imp phase);
  uvm_phase_schedule current_phase;
  current_phase = get_current_phase();
  current_phase.jump(phase);
endfunction

function void uvm_component::jump_all_domains(uvm_phase_imp phase);
  uvm_phase_schedule current_phase;
  current_phase = get_current_phase();
  current_phase.jump_all(phase);
endfunction

function void uvm_component::agree_to_terminate_phase();
  uvm_phase_schedule current_phase;
  current_phase = get_current_phase();
  current_phase.agree_to_terminate_phase();
endfunction

function void uvm_component::disagree_to_terminate_phase();
  uvm_phase_schedule current_phase;
  current_phase = get_current_phase();
  current_phase.disagree_to_terminate_phase();
endfunction

function void uvm_component::terminate_phase();
  uvm_phase_schedule current_phase;
  current_phase = get_current_phase();
  current_phase.terminate_phase();
endfunction


// do_kill_all
// -----------

function void uvm_component::do_kill_all();
  foreach(m_children[c])
    m_children[c].do_kill_all();
  kill();
endfunction


// kill
// ----

function void uvm_component::kill();
  `ifdef UVM_USE_FPC
    if (m_phase_process != null) begin
      m_phase_process.kill;
      m_phase_process = null;
    end
  `else
     ->m_kill_request;
  `endif
endfunction


// suspend
// -------

task uvm_component::suspend();
  `ifdef UVM_USE_FPC
    if(m_phase_process != null)
      m_phase_process.suspend;
  `else
    uvm_report_error("UNIMP", "suspend not implemented", UVM_NONE);
  `endif
endtask


// resume
// ------

task uvm_component::resume();
  `ifdef UVM_USE_FPC
    if(m_phase_process!=null) 
      m_phase_process.resume;
  `else
     uvm_report_error("UNIMP", "resume not implemented", UVM_NONE);
  `endif
endtask


// restart
// -------

task uvm_component::restart();
  uvm_report_warning("UNIMP",
      $psprintf("%0s: restart not implemented",this.get_name()), UVM_NONE);
endtask


// status
//-------

function string uvm_component::status();

  `ifdef UVM_USE_FPC
    process::state ps;

    if(m_phase_process == null)
      return "<unknown>";

    ps = m_phase_process.status();

    return ps.name();
  `else
     uvm_report_error("UNIMP", "status not implemented", UVM_NONE);
  `endif

endfunction


// stop
// ----

task uvm_component::stop(string ph_name);
  return;
endtask


// resolve_bindings
// ----------------

function void uvm_component::resolve_bindings();
  return;
endfunction


// do_resolve_bindings
// -------------------

function void uvm_component::do_resolve_bindings();
  foreach( m_children[s] )
    m_children[s].do_resolve_bindings();
  resolve_bindings();
endfunction



//------------------------------------------------------------------------------
//
// Recording interface
//
//------------------------------------------------------------------------------

// accept_tr
// ---------

function void uvm_component::accept_tr (uvm_transaction tr,
                                        time accept_time=0);
  uvm_event e;
  tr.accept_tr(accept_time);
  do_accept_tr(tr);
  e = event_pool.get("accept_tr");
  if(e!=null) 
    e.trigger();
endfunction

// begin_tr
// --------

function integer uvm_component::begin_tr (uvm_transaction tr,
                                          string stream_name ="main",
                                          string label="",
                                          string desc="",
                                          time begin_time=0);
  return m_begin_tr(tr, 0, 0, stream_name, label, desc, begin_time);
endfunction

// begin_child_tr
// --------------

function integer uvm_component::begin_child_tr (uvm_transaction tr,
                                          integer parent_handle=0,
                                          string stream_name="main",
                                          string label="",
                                          string desc="",
                                          time begin_time=0);
  return m_begin_tr(tr, parent_handle, 1, stream_name, label, desc, begin_time);
endfunction

// m_begin_tr
// ----------

function integer uvm_component::m_begin_tr (uvm_transaction tr,
                                          integer parent_handle=0,
                                          bit    has_parent=0,
                                          string stream_name="main",
                                          string label="",
                                          string desc="",
                                          time begin_time=0);
  uvm_event e;
  integer stream_h;
  integer tr_h;
  integer link_tr_h;
  string name;

  tr_h = 0;
  if(has_parent)
    link_tr_h = tr.begin_child_tr(begin_time, parent_handle);
  else
    link_tr_h = tr.begin_tr(begin_time);

  if (tr.get_name() != "")
    name = tr.get_name();
  else
    name = tr.get_type_name();

  if(stream_name == "") stream_name="main";

  if (uvm_verbosity'(recording_detail) != UVM_NONE) begin

    if(m_stream_handle.exists(stream_name))
        stream_h = m_stream_handle[stream_name];

    if (uvm_check_handle_kind("Fiber", stream_h) != 1) 
      begin  
        stream_h = uvm_create_fiber(stream_name, "TVM", get_full_name());
        m_stream_handle[stream_name] = stream_h;
      end

    if(has_parent == 0) 
      tr_h = uvm_begin_transaction("Begin_No_Parent, Link", 
                             stream_h,
                             name,
                             label,
                             desc,
                             begin_time);
    else begin
      tr_h = uvm_begin_transaction("Begin_End, Link", 
                             stream_h,
                             name,
                             label,
                             desc,
                             begin_time);
      if(parent_handle!=0)
        uvm_link_transaction(parent_handle, tr_h, "child");
    end

    m_tr_h[tr] = tr_h;

    if (uvm_check_handle_kind("Transaction", link_tr_h) == 1)
      uvm_link_transaction(tr_h,link_tr_h);
        
    do_begin_tr(tr,stream_name,tr_h); 
        
  end
 
  e = event_pool.get("begin_tr");
  if (e!=null) 
    e.trigger(tr);
        
  return tr_h;

endfunction


// end_tr
// ------

function void uvm_component::end_tr (uvm_transaction tr,
                                     time end_time=0,
                                     bit free_handle=1);
  uvm_event e;
  integer tr_h;
  tr_h = 0;

  tr.end_tr(end_time,free_handle);

  if (uvm_verbosity'(recording_detail) != UVM_NONE) begin

    if (m_tr_h.exists(tr)) begin

      tr_h = m_tr_h[tr];

      do_end_tr(tr, tr_h); // callback

      m_tr_h.delete(tr);

      if (uvm_check_handle_kind("Transaction", tr_h) == 1) begin  

        uvm_default_recorder.tr_handle = tr_h;
        tr.record(uvm_default_recorder);

        uvm_end_transaction(tr_h,end_time);

        if (free_handle)
           uvm_free_transaction_handle(tr_h);

      end
    end
    else begin
      do_end_tr(tr, tr_h); // callback
    end

  end

  e = event_pool.get("end_tr");
  if(e!=null) 
    e.trigger();

endfunction

// record_error_tr
// ---------------

function integer uvm_component::record_error_tr (string stream_name="main",
                                              uvm_object info=null,
                                              string label="error_tr",
                                              string desc="",
                                              time   error_time=0,
                                              bit    keep_active=0);
  string etype;
  integer stream_h;

  if(keep_active) etype = "Error, Link";
  else etype = "Error";

  if(error_time == 0) error_time = $time;

  stream_h = m_stream_handle[stream_name];
  if (uvm_check_handle_kind("Fiber", stream_h) != 1) begin  
    stream_h = uvm_create_fiber(stream_name, "TVM", get_full_name());
    m_stream_handle[stream_name] = stream_h;
  end

  record_error_tr = uvm_begin_transaction(etype, stream_h, label,
                         label, desc, error_time);
  if(info!=null) begin
    uvm_default_recorder.tr_handle = record_error_tr;
    info.record(uvm_default_recorder);
  end

  uvm_end_transaction(record_error_tr,error_time);
endfunction


// record_event_tr
// ---------------

function integer uvm_component::record_event_tr (string stream_name="main",
                                              uvm_object info=null,
                                              string label="event_tr",
                                              string desc="",
                                              time   event_time=0,
                                              bit    keep_active=0);
  string etype;
  integer stream_h;

  if(keep_active) etype = "Event, Link";
  else etype = "Event";

  if(event_time == 0) event_time = $time;

  stream_h = m_stream_handle[stream_name];
  if (uvm_check_handle_kind("Fiber", stream_h) != 1) begin  
    stream_h = uvm_create_fiber(stream_name, "TVM", get_full_name());
    m_stream_handle[stream_name] = stream_h;
  end

  record_event_tr = uvm_begin_transaction(etype, stream_h, label,
                         label, desc, event_time);
  if(info!=null) begin
    uvm_default_recorder.tr_handle = record_event_tr;
    info.record(uvm_default_recorder);
  end

  uvm_end_transaction(record_event_tr,event_time);
endfunction

// do_accept_tr
// ------------

function void uvm_component::do_accept_tr (uvm_transaction tr);
  return;
endfunction


// do_begin_tr
// -----------

function void uvm_component::do_begin_tr (uvm_transaction tr,
                                          string stream_name,
                                          integer tr_handle);
  return;
endfunction


// do_end_tr
// ---------

function void uvm_component::do_end_tr (uvm_transaction tr,
                                        integer tr_handle);
  return;
endfunction


//------------------------------------------------------------------------------
//
// Configuration interface
//
//------------------------------------------------------------------------------


// set_config_int
// --------------

function void  uvm_component::set_config_int    (string      inst_name,
                                                 string      field_name,
                                                 uvm_bitstream_t value);
  uvm_int_config_setting cfg;
  cfg = new(inst_name, field_name, value, this);
  m_config_set = 1;
  m_configuration_table.push_front(cfg);
endfunction


// set_config_string
// -----------------

function void uvm_component::set_config_string  (string      inst_name,  
                                                 string      field_name,
                                                 string      value);
  uvm_string_config_setting cfg;
  cfg = new(inst_name, field_name, value, this);
  m_config_set = 1;
  m_configuration_table.push_front(cfg);
endfunction


// set_config_object
// -----------------

function void uvm_component::set_config_object  (string      inst_name,
                                                 string      field_name,
                                                 uvm_object  value,
                                                 bit         clone=1);
  uvm_object_config_setting cfg;
  if(clone && (value != null)) begin
    uvm_object tmp;
    tmp = value.clone();

    // If create not implemented, or clone is attempted on objects that
    // do not t allow cloning (e.g. components) clone will return null.
    if(tmp == null) begin
      uvm_component comp;
      if ($cast(comp,value)) begin
        uvm_report_error("INVCLNC", {"Clone failed during set_config_object ",
          "with an object that is an uvm_component. Components cannot be cloned."}, UVM_NONE);
        return;
      end
      else begin
        uvm_report_warning("INVCLN", {"Clone failed during set_config_object, ",
          "the original reference will be used for configuration. Check that ",
          "the create method for the object type is defined properly."}, UVM_NONE);
      end
    end
    else
      value = tmp;
  end

  cfg = new(inst_name, field_name, value, this, clone);
  m_config_set = 1;
  m_configuration_table.push_front(cfg);

endfunction


// m_component_path
// ----------------

function void uvm_component::m_component_path(ref uvm_component path[$]);
  uvm_component comp;
  comp = this;
  `uvm_clear_queue(path)
  while(comp != null) begin
    path.push_front(comp);
    comp = comp.get_parent();
  end
endfunction


// m_get_config_matches
// --------------------

function void uvm_component::m_get_config_matches(
      ref uvm_config_setting cfg_matches[$], 
      input uvm_config_setting::uvm_config_type cfgtype, string field_name);
  uvm_component comp;
  static uvm_component stack[$];
  static uvm_config_setting comp_matches[$];

  comp = this;

  `uvm_clear_queue(cfg_matches)


  //Get the path up to the root. Since configs are done in groups for a comp,
  //cache the set of config matches from the last check to reduce searching.
  if((stack.size() == 0) || (stack[stack.size()-1] != this) || (m_config_set == 1)) begin
    m_config_set = 0;
    m_component_path(stack);
    `uvm_clear_queue(comp_matches);
    foreach(stack[i]) begin
      for(int j=0; j<stack[i].m_configuration_table.size(); ++j) begin
         if(stack[i].m_configuration_table[j].component_match(this)) 
           comp_matches.push_back(stack[i].m_configuration_table[j]);
      end
    end
  end

  foreach(comp_matches[i]) begin
    if(comp_matches[i].field_match(field_name) &&
         ((comp_matches[i].get_value_type() == cfgtype) ||
          (cfgtype == uvm_config_setting::UVM_UNDEFINED_TYPE))) 
    begin
       cfg_matches.push_back(comp_matches[i]);
    end
  end

endfunction


// check_config_usage
// ------------------

function void uvm_component::check_config_usage ( bit recurse=1 );
  uvm_config_setting cfg;
  bit found;
  string fstr, applied_str, cfg_type;

  found=0; 

  if(recurse)
    foreach(m_children[i])  begin
      m_children[i].check_config_usage(recurse);
    end

  if(m_configuration_table.size() == 0) return;

  if(this == uvm_top)
    fstr = "from the GLOBAL scope";
  else
    fstr = {"from component ", get_full_name(), "(", 
             get_type_name(), ")"};

  foreach(m_configuration_table[i]) begin
    cfg = m_configuration_table[i];
    if(cfg.m_used_list.size() == 0 &&
       cfg.m_override_list.size() == 0 )
    begin
      if(cfg.get_value_type() == uvm_config_setting::UVM_INT_TYPE)
        cfg_type = "int";
      else if(cfg.get_value_type() == uvm_config_setting::UVM_STRING_TYPE)
        cfg_type = "string";
      else
        cfg_type = "object";
      uvm_report_warning("CFGNTS", {"No get_config_",cfg_type,
         "() call ever matched the following set_config_", cfg_type, "() call ", fstr,
         ": ", cfg.convert2string()}, UVM_NONE);
    end 
  end

  //Do not do the lookup work if the CFGOVR action is off
  if(uvm_report_enabled(UVM_LOW, UVM_INFO, "CFGOVR"))
  foreach(m_configuration_table[i]) begin
    cfg = m_configuration_table[i];
    if(cfg.m_override_list.size() != 0)
    begin
      uvm_report_info("CFGOVR", {"The configuration setting ", cfg.convert2string(), " ", fstr, " was overridden by config setting ", cfg.m_override_list[0].convert2string(), " from component ", cfg.m_override_list[0].m_from.get_full_name(), "(",  cfg.m_override_list[0].m_from.get_type_name(), ")"}, UVM_NONE);
    end
  end

  //Do not do the lookup work if the CFGSET action is off
  if(uvm_report_enabled(UVM_LOW, UVM_INFO, "CFGSET"))
  foreach(m_configuration_table[i]) begin
    string cfgstr;
    cfg = m_configuration_table[i];
    if(cfg.m_used_list.size() != 0)
      begin
        cfgstr = cfg.convert2string();
        applied_str = "";
        for(int j=0; j<cfg.m_used_list.size(); ++j) begin
          uvm_report_info("CFGSET", {"The configuration setting ", cfgstr, " ", fstr, " was applied to component: ", cfg.m_used_list[j].get_full_name(), " (",  cfg.m_used_list[j].get_type_name(), ")"}, UVM_NONE);
        end
      end 
  end

endfunction


// get_config_int
// --------------

function bit uvm_component::get_config_int (string field_name,
                                            inout uvm_bitstream_t value);
  static uvm_config_setting cfg_matches[$];
  uvm_int_config_setting cfg;
  uvm_component c;
  //Scan the config tables of each component in the path
  m_get_config_matches(cfg_matches, uvm_config_setting::UVM_INT_TYPE, field_name);

  //The first match is the override
  if(cfg_matches.size()) begin
    $cast(cfg, cfg_matches[0]);
    if(print_config_matches)
      cfg_matches[0].print_match(this, cfg_matches[0].get_from_component(), field_name);
    cfg_matches[0].set_used(this);
    for(int i=1; i<cfg_matches.size(); ++i) begin
      cfg_matches[i].set_override(cfg_matches[0]);
    end
    value = cfg.m_value;
    return 1;
  end

  return 0;
endfunction
  

// get_config_string
// -----------------

function bit uvm_component::get_config_string (string field_name,
                                               inout string value);
  static uvm_config_setting cfg_matches[$];
  uvm_string_config_setting cfg;
  uvm_component c;

  //Scan the config tables of each component in the path
  m_get_config_matches(cfg_matches, uvm_config_setting::UVM_STRING_TYPE, field_name);

  //The first match is the override
  if(cfg_matches.size()) begin
    $cast(cfg, cfg_matches[0]);
    if(print_config_matches)
      cfg_matches[0].print_match(this, cfg_matches[0].get_from_component(), field_name);
    cfg_matches[0].set_used(this);
    for(int i=1; i<cfg_matches.size(); ++i)
      cfg_matches[i].set_override(cfg_matches[0]);
    value = cfg.m_value;
    return 1;
  end

  return 0;
endfunction

  
// get_config_object
// -----------------

function bit uvm_component::get_config_object (string field_name,
                                               inout uvm_object value,  
                                               input bit clone=1);
  static uvm_config_setting cfg_matches[$];
  uvm_object_config_setting cfg;
  uvm_component c;

  //Scan the config tables of each component in the path
  m_get_config_matches(cfg_matches, uvm_config_setting::UVM_OBJECT_TYPE, field_name);

  //The first match is the override
  if(cfg_matches.size()) begin
    $cast(cfg, cfg_matches[0]);
    if(print_config_matches)
      cfg_matches[0].print_match(this, cfg_matches[0].get_from_component(), field_name);
    cfg_matches[0].set_used(this);
    for(int i=1; i<cfg_matches.size(); ++i)
      cfg_matches[i].set_override(cfg_matches[0]);
    if((clone && cfg.m_clone) && (cfg.m_value != null))
      value = cfg.m_value.clone();
    else
      value = cfg.m_value;
    return 1;
  end

  return 0;
endfunction
 

// apply_config_settings
// ---------------------

function void uvm_component::apply_config_settings (bit verbose=0);
  static uvm_component stack[$];
  static uvm_config_setting overrides[string];
  uvm_config_setting cfg;
  uvm_int_config_setting cfg_int;
  uvm_string_config_setting cfg_str;
  uvm_object_config_setting cfg_obj;
  uvm_component comp;
  string match_str;
  string matched="";
  bit has_match=0;
  if(stack.size() == 0 || stack[stack.size()-1] != this) begin
    m_component_path(stack);
  end
  //apply any override that matches this component. Go bottom up and then back
  //to front so the last override in the global scope has precedence to the
  //first override in the parent scope.
  if (verbose) begin
    match_str = {"Auto-configuration matches for component ",
       this.get_full_name()," (",get_type_name(),"). Last entry for a given field takes precedence.\n\n",
       "   Config set from  Instance Path     Field name   Type    Value\n",
       "   ------------------------------------------------------------------------------\n"};
  end
  for(int i=stack.size()-1; i>=0; --i) begin
    comp = stack[i];
    if(comp == null) comp = uvm_top;
    if(comp!=null) begin
      for(int j=comp.m_configuration_table.size()-1; j>=0; --j) begin
        cfg = comp.m_configuration_table[j];
        if(cfg.component_match(this)) begin
          if(verbose)
            matched = cfg.matches_string(this,comp);
          if($cast(cfg_int, cfg))
             set_int_local(cfg_int.m_field, cfg_int.m_value);
          else if($cast(cfg_str, cfg))
            set_string_local(cfg_str.m_field, cfg_str.m_value);
          else if($cast(cfg_obj, cfg)) begin
            set_object_local(cfg_obj.m_field, cfg_obj.m_value, cfg_obj.m_clone);
            if(verbose)
              matched = {matched, " clone=",(cfg_obj.m_clone==1)?"1":"0"};
          end
          if(verbose)
            match_str = {match_str, "  ", matched,"\n"};
          has_match = 1;
          if(m_sc.status)
            cfg.m_used_list.push_back(this);
        end
      end
    end
  end

  if (verbose && has_match)
    if(uvm_report_enabled(UVM_MEDIUM, UVM_INFO, "auto-configuration"))
      uvm_report_info("auto-configuration", {match_str,"\n"}, UVM_MEDIUM);

endfunction


// print_config_settings
// ---------------------

function void uvm_component::print_config_settings (string field="",
                                                    uvm_component comp=null,
                                                    bit recurse=0);
  static int depth;
  static uvm_component stack[$];
  uvm_component cc;
  string all_matches;
  string v,r;
  all_matches = "";

  if(comp==null)
    comp = this;

  comp.m_component_path(stack);
  while(stack.size() && (stack[stack.size()-1] != comp))
    void'(stack.pop_back());

  cc = comp;

  $swrite(v, "%s", cc.get_full_name());
  while(v.len()<17) v = {v," "};
  foreach(stack[s]) begin
    comp = stack[s];
    for(int i=0; i<comp.m_configuration_table.size(); ++i) begin
      r = comp.m_configuration_table[i].matches_string(cc, comp);
      if(r != "")
        all_matches = {all_matches, v, r, "\n"};
    end
  end

  // Note- should use uvm_printer for formatting
  if(((all_matches != "") || (recurse == 1)) && depth == 0) begin
    $display("Configuration settings for component %s (recurse = %0d)",
             cc.get_full_name(), recurse);
    $display("Set to            Set from         Component match   Field name   Type    Value");
    $display("-------------------------------------------------------------------------------");
  end
  if(all_matches == "")
    $display("%s NONE", v);
  else
    $write("%s", all_matches);

  if(recurse) begin
    depth++;
    if(cc.m_children.first(v))
      do this.print_config_settings(field, cc.m_children[v], recurse);
      while(cc.m_children.next(v));
    depth--;
  end
endfunction


// do_print (override)
// --------

function void uvm_component::do_print(uvm_printer printer);
  string v;
  super.do_print(printer);

  // It is printed only if its value is other than the default (UVM_NONE)
  if(uvm_verbosity'(recording_detail) != UVM_NONE)
    case (recording_detail)
      UVM_LOW : printer.print_generic("recording_detail", "uvm_verbosity", 
        $bits(recording_detail), "UVM_LOW");
      UVM_MEDIUM : printer.print_generic("recording_detail", "uvm_verbosity", 
        $bits(recording_detail), "UVM_MEDIUM");
      UVM_HIGH : printer.print_generic("recording_detail", "uvm_verbosity", 
        $bits(recording_detail), "UVM_HIGH");
      UVM_FULL : printer.print_generic("recording_detail", "uvm_verbosity", 
        $bits(recording_detail), "UVM_FULL");
      default : printer.print_field("recording_detail", recording_detail, 
        $bits(recording_detail), UVM_DEC, , "integral");
    endcase

  if (enable_stop_interrupt != 0) begin
    printer.print_field("enable_stop_interrupt", enable_stop_interrupt,
                        $bits(enable_stop_interrupt), UVM_BIN, ".", "bit");
  end

endfunction


// set_int_local (override)
// -------------

function void uvm_component::set_int_local (string field_name,
                             uvm_bitstream_t value,
                             bit recurse=1);

  //call the super function to get child recursion and any registered fields
  super.set_int_local(field_name, value, recurse);

  //set the local properties
  if(uvm_is_match(field_name, "recording_detail"))
    recording_detail = value;

endfunction


