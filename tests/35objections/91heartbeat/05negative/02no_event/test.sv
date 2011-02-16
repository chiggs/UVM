module test;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class my_catcher extends uvm_report_catcher;
     int cnt = 0;
     string msg = "";
     bit times[time];

     uvm_component c;
     virtual function action_e catch();
        if(get_id()!="NOEVNT") return THROW;
        $display("%0t: MSG: %s", $time, get_message());
        cnt++;
        msg = get_message();
        times[$time] = 1;
        return CAUGHT;
     endfunction
  endclass

  uvm_callbacks_objection myobj = new("myobj");

  class mycomp extends uvm_component;
    time del;
    function new(string name, uvm_component parent);
      super.new(name,parent);
    endfunction
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      repeat(10) #del begin
        myobj.raise_objection(this);
      end
      phase.drop_objection(this);
    endtask
  endclass
  class myagent extends uvm_component;
    mycomp mc1, mc2;
    function new(string name, uvm_component parent);
      super.new(name,parent);
      mc1 = new("mc1", this);
      mc2 = new("mc2", this);
      mc1.del = 45;
      mc2.del = 55;
    endfunction
  endclass
  class myenv extends uvm_component;
    uvm_heartbeat hb;
    myagent agent;

    function new(string name, uvm_component parent);
      super.new(name,parent);
      agent = new("agent", this);

      hb = new("myhb", this, myobj);
      hb.add(agent.mc1);
      hb.add(agent.mc2);
    endfunction
    task run_phase(uvm_phase phase);
      uvm_component l[$];
      phase.raise_objection(this);
      //This is an error because start was called with no event and 
      //none is set.
      #10 hb.start();

      //This one is okay because the null event says to use one if it
      //exists. If not, then don't start.
      #50 hb.set_heartbeat(null,l);

      //This is an error because start was called with no event and 
      //none is set. Make sure that set_heartbeat didn't mess up the
      //state.
      #40 hb.start();

      phase.drop_objection(this);
    endtask
  endclass

  class test extends uvm_test;
    myenv env;
    my_catcher mc;
    `uvm_component_utils(test)
    function new(string name, uvm_component parent);
      super.new(name,parent);
      env = new("env", this);
      mc = new;
      uvm_report_cb::add(null,mc);
    endfunction 
    function void report;
      uvm_report_object r;
      if(mc.cnt != 2) begin
        $display("** UVM TEST FAILED **");
        return;
      end
      if(!mc.times.exists(10) || !mc.times.exists(100)) begin
        $display("** UVM TEST FAILED **");
        return;
      end
      if(mc.msg != "start() was called for: myhb with a null trigger and no currently set trigger") begin
        $display("** UVM TEST FAILED **");
        return;
      end
      $display("** UVM TEST PASSED **");
    endfunction
  
  endclass

  initial run_test();
endmodule
