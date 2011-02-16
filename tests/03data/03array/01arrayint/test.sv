//---------------------------------------------------------------------- 
//   Copyright 2010 Cadence Design Systems, Inc.
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

//Field Macros:
//This test verifies that the basic funcitonality in uvm_field_int
//macro works as expected.
//
//The macros which are tested are:
//  `uvm_field_int

//Pass/Fail criteria:
//  The copy, compare, pack, unpack, print, record and set_config_int must
//  produce the correct results.
//

module test;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class myobject extends uvm_sequence_item;
    int iv[];
    byte b[];
    logic [127:0] bigint[];

    `uvm_object_utils_begin(myobject)
      `uvm_field_array_int(iv, UVM_DEFAULT)
      `uvm_field_array_int(b, UVM_DEFAULT)
      `uvm_field_array_int(bigint, UVM_DEFAULT)
    `uvm_object_utils_end
  endclass

  class test extends uvm_test;
    int cfg_field_set[];
    int cfg_field_notset[];

    `uvm_new_func
    `uvm_component_utils_begin(test)
      `uvm_field_array_int(cfg_field_set, UVM_DEFAULT)
      `uvm_field_array_int(cfg_field_notset, UVM_DEFAULT)
    `uvm_component_utils_end

    myobject obj = new;
    task run;
      byte unsigned bytes[];
      myobject cp;
      string exp = {
        "----------------------------------------------------------------------\n",
        "Name                     Type                Size                Value\n",
        "----------------------------------------------------------------------\n",
        "obj                      myobject            -                       -\n",
        "  iv                     da(integral)        5                       -\n",
        "    [0]                  integral            32                 'h5555\n",
        "    [1]                  integral            32                 'h5556\n",
        "    [2]                  integral            32                 'h5557\n",
        "    [3]                  integral            32                 'h5558\n",
        "    [4]                  integral            32                 'h5559\n",
        "  b                      da(integral)        5                       -\n",
        "    [0]                  integral            8                    'haa\n",
        "    [1]                  integral            8                    'hab\n",
        "    [2]                  integral            8                    'h53\n",
        "    [3]                  integral            8                    'had\n",
        "    [4]                  integral            8                    'hae\n",
        "  bigint                 da(integral)        5                       -\n",
        "    [0]                  integral            128  'haaaa5555aaaa5555a+\n",
        "    [1]                  integral            128  'haaaa5555aaaa5555a+\n",
        "    [2]                  integral            128  'haaaa5555aaaa5555a+\n",
        "    [3]                  integral            128  'haaaa5555aaaa5555a+\n",
        "    [4]                  integral            128  'haaaa5555aaaa5555a+\n",
        "----------------------------------------------------------------------\n"
      };

      obj.set_name("obj");

      if(cfg_field_set.size() != 3)
        uvm_report_info("FAILED", "*** UVM TEST FAILED cfg_field is not set ***", UVM_NONE);
      else begin
        for(int i=0; i<3; ++i)
          if(cfg_field_set[i] != 'haa+i)
            uvm_report_info("FAILED", $sformatf("*** UVM TEST FAILED cfg_field[%0d] is not set ***",i), UVM_NONE);
      end
      if(cfg_field_notset.size() != 0)
        uvm_report_info("FAILED", "*** UVM TEST FAILED cfg_field_notset is set ***", UVM_NONE);
 
      obj.b = new[5]; obj.iv = new[5]; obj.bigint = new[5]; 
      for(int i=0; i<5; ++i) begin 
        obj.b[i] = 'haa + i;
        obj.iv[i] = 'h5555 + i;
        obj.bigint[i] = 128'haaaa5555aaaa5555aaaa5555 + i;
      end

      $cast(cp, obj.clone());
      cp.set_name("obj_copy");

      // This tests the copy and the compare
      if(!cp.compare(obj))
        uvm_report_info("FAILED", "*** UVM TEST FAILED compare failed, expected to pass ***", UVM_NONE);

      cp.b[2] = ~cp.b[2];
      if(cp.compare(obj))
        uvm_report_info("FAILED", "*** UVM TEST FAILED compare passed, expected to fail ***", UVM_NONE);

      uvm_default_packer.use_metadata = 1;
      void'(cp.pack_bytes(bytes));
      if(bytes.size() != 117)
        uvm_report_info("FAILED", "*** UVM TEST FAILED compare passed, packed incorrectly ***", UVM_NONE);

      void'(obj.unpack_bytes(bytes));
      if(!cp.compare(obj))
        uvm_report_info("FAILED", "*** UVM TEST FAILED unpack failed ***", UVM_NONE);


      uvm_default_printer.knobs.reference=0;
      //if(exp != obj.sprint())
      //  uvm_report_info("FAILED", "*** UVM TEST FAILED print failed ***", UVM_NONE);

      obj.print();
      uvm_report_info("PASSED", "*** UVM TEST PASSED ***", UVM_NONE);

      recording_detail=UVM_LOW;
      void'(begin_tr(obj));
      end_tr(obj);

    endtask
  endclass

  initial begin
    uvm_default_printer = uvm_default_line_printer;
    set_config_int("*", "cfg_field_set", 3);
    for(int i=0;i<3;++i)
      set_config_int("*", $sformatf("cfg_field_set[%0d]",i), 'haa+i);
    run_test();
  end

endmodule
