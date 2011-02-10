//----------------------------------------------------------------------
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
//----------------------------------------------------------------------


//------------------------------------------------------------------------------
//
// CLASS: uvm_sequencer #(REQ,RSP)
//
//------------------------------------------------------------------------------

class uvm_sequencer #(type REQ=uvm_sequence_item, RSP=REQ)
                                   extends uvm_sequencer_param_base #(REQ, RSP);

  typedef uvm_sequencer #( REQ , RSP) this_type;

  bit sequence_item_requested = 0;
  bit get_next_item_called    = 0;

  `uvm_component_param_utils(this_type)

  // Variable: seq_item_export
  //
  // This export provides access to this sequencer's implementation of the
  // sequencer interface, <uvm_sqr_if_base #(REQ,RSP)>, which defines the following
  // methods:
  //
  //| Requests:
  //|  virtual task          get_next_item      (output REQ request);
  //|  virtual task          try_next_item      (output REQ request);
  //|  virtual task          get                (output REQ request);
  //|  virtual task          peek               (output REQ request);
  //| Responses:
  //|  virtual function void item_done          (input RSP response=null);
  //|  virtual task          put                (input RSP response);
  //| Sync Control:
  //|  virtual task          wait_for_sequences ();
  //|  virtual function bit  has_do_available   ();
  //
  // See <uvm_sqr_if_base #(REQ,RSP)> for information about this interface.

  uvm_seq_item_pull_imp #(REQ, RSP, this_type) seq_item_export;



  // Function: new
  //
  // Standard component constructor that creates an instance of this class
  // using the given ~name~ and ~parent~, if any.
  //
  extern function new (string name, uvm_component parent=null);
  

  // Function: stop_sequences
  //
  // Tells the sequencer to kill all sequences and child sequences currently
  // operating on the sequencer, and remove all requests, locks and responses
  // that are currently queued.  This essentially resets the sequencer to an
  // idle state.
  //
  extern virtual function void stop_sequences();


  extern virtual function string get_type_name();

  
  //-----------------
  // Internal Methods
  //-----------------
  // Do not use directly; not part of standard

  // Access to following internal methods provided via seq_item_export
  extern virtual task          get_next_item (output REQ t);
  extern virtual task          try_next_item (output REQ t);
  extern virtual function void item_done     (RSP item = null);
  extern virtual task          put           (RSP t);
  extern task                  get           (output REQ t);
  extern task                  peek          (output REQ t);
  extern function void         item_done_trigger(RSP item = null);
  function RSP                 item_done_get_trigger_data();
    return last_rsp(0);
  endfunction

  extern protected virtual function int m_find_number_driver_connections();

endclass  


typedef uvm_sequencer #(uvm_sequence_item) uvm_virtual_sequencer;



//------------------------------------------------------------------------------
// IMPLEMENTATION
//------------------------------------------------------------------------------

// Function: new
//
// Standard component constructor that creates an instance of this class
// using the given ~name~ and ~parent~, if any.
//
function uvm_sequencer::new (string name, uvm_component parent=null);
  super.new(name, parent);
  seq_item_export = new ("seq_item_export", this);
endfunction


// Function: stop_sequences
//
// Tells the sequencer to kill all sequences and child sequences currently
// operating on the sequencer, and remove all requests, locks and responses
// that are currently queued.  This essentially resets the sequencer to an
// idle state.
//
function void uvm_sequencer::stop_sequences();
  REQ t;
  super.stop_sequences();
  sequence_item_requested  = 0;
  get_next_item_called     = 0;
  // Empty the request fifo
  if (m_req_fifo.used()) begin
    uvm_report_info(get_full_name(), "Sequences stopped.  Removing request from sequencer fifo");
    while (m_req_fifo.try_get(t));
  end
endfunction


function string uvm_sequencer::get_type_name();
  return "uvm_sequencer";
endfunction 


//-----------------
// Internal Methods
//-----------------

// m_find_number_driver_connections
// --------------------------------
// Counting the number of of connections is done at end of
// elaboration and the start of run.  If the user neglects to
// call super in one or the other, the sequencer will still
// have the correct value

function int uvm_sequencer::m_find_number_driver_connections();
  uvm_port_component_base provided_to_port_list[string];
  uvm_port_component_base seq_port_base;
  
  // Check that the seq_item_pull_port is connected
  seq_port_base = seq_item_export.get_comp();
  seq_port_base.get_provided_to(provided_to_port_list);
  return provided_to_port_list.num();
endfunction


// get_next_item
// -------------

task uvm_sequencer::get_next_item(output REQ t);
  REQ req_item;

  // If a sequence_item has already been requested, then get_next_item()
  // should not be called again until item_done() has been called.

  if (get_next_item_called == 1)
    uvm_report_error(get_full_name(),
      "Get_next_item called twice without item_done or get in between", UVM_NONE);
  
  if (!sequence_item_requested)
    m_select_sequence();

  // Set flag indicating that the item has been requested to ensure that item_done or get
  // is called between requests
  sequence_item_requested = 1;
  get_next_item_called = 1;
  m_req_fifo.peek(t);
endtask


// try_next_item
// -------------

task uvm_sequencer::try_next_item(output REQ t);
  int selected_sequence;
  time arb_time;

  if (get_next_item_called == 1) begin
    uvm_report_error(get_full_name(), "get_next_item/try_next_item called twice without item_done or get in between", UVM_NONE);
    return;
  end
    
  // allow state from last transaction to settle such that sequences'
  // relevancy can be determined with up-to-date information
  wait_for_sequences();

  // choose the sequence based on relevancy
  selected_sequence = m_choose_next_request();

  // return if none available
  if (selected_sequence == -1) begin
    t = null;
    return;
  end

  // now, allow chosen sequence to resume
  m_set_arbitration_completed(arb_sequence_q[selected_sequence].request_id);
  arb_sequence_q.delete(selected_sequence);
  m_update_lists();
  sequence_item_requested = 1;
  get_next_item_called = 1;

  // give it one NBA to put a new item in the fifo
  wait_for_sequences();

  // attempt to get the item; if it fails, produce an error and return
  if (!m_req_fifo.try_peek(t))
  $display("%p %p",arb_sequence_q[selected_sequence],
                arb_sequence_q[selected_sequence].sequence_ptr);
    uvm_report_error(get_full_name(), {"try_next_item: selected sequence '",
      arb_sequence_q[selected_sequence].sequence_ptr.get_full_name(),
      "' did not produce an item within an nba delay"}, UVM_NONE);

endtask


// item_done
// ---------

function void uvm_sequencer::item_done(RSP item = null);
  REQ t;

  // Set flag to allow next get_next_item or peek to get a new sequence_item
  sequence_item_requested = 0;
  get_next_item_called = 0;
  
  if (m_req_fifo.try_get(t) == 0) begin
    uvm_report_fatal(get_full_name(), {"Item_done() called with no outstanding requests.",
      " Each call to item_done() must be paired with a previous call to get_next_item()."});
  end else begin
    m_wait_for_item_sequence_id = t.get_sequence_id();
    m_wait_for_item_transaction_id = t.get_transaction_id();
  end
  
  if (item != null) begin
    seq_item_export.put_response(item);
  end

  // Grant any locks as soon as possible
  grant_queued_locks();
endfunction


// put
// ---

task uvm_sequencer::put (RSP t);
  put_response(t);
endtask


// get
// ---

task uvm_sequencer::get(output REQ t);
  if (sequence_item_requested == 0) begin
    m_select_sequence();
  end
  sequence_item_requested = 1;
  m_req_fifo.peek(t);
  item_done();
endtask


// peek
// ----

task uvm_sequencer::peek(output REQ t);

  if (sequence_item_requested == 0) begin
    m_select_sequence();
  end
  
  // Set flag indicating that the item has been requested to ensure that item_done or get
  // is called between requests
  sequence_item_requested = 1;
  m_req_fifo.peek(t);
endtask


// item_done_trigger
// -----------------

function void uvm_sequencer::item_done_trigger(RSP item = null);
  item_done(item);
endfunction



