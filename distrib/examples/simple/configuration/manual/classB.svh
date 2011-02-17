//----------------------------------------------------------------------
//   Copyright 2007-2011 Mentor Graphics Corporation
//   Copyright 2007-2011 Cadence Design Systems, Inc.
//   Copyright 2010-2011 Synopsys, Inc.
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
//----------------------------------------------------------------------
`ifndef CLASSB_SVH
`define CLASSB_SVH

`include "classC.svh"

class B extends uvm_component;
  bit debug = 0;
  C u1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    void'(get_config_int("debug", debug));
    set_config_int("u1", "v", 0);

    $display("%s: In Build: debug = %0d", get_full_name(), debug);

    u1 = new("u1", this);
  endfunction

  function string get_type_name();
    return "B";
  endfunction
  function void do_print(uvm_printer printer);
    printer.print_field("debug", debug, 1);
  endfunction
endclass

`endif
