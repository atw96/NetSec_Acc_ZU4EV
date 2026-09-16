// Minimal compilable UVM smoke for netsec_datapath (QuestaSim / UVM-1.2)
// Run: see tb/uvm_env/run_questa.do
`timescale 1ns/1ps

interface netsec_if(input logic clk, input logic rst_n);
    logic [7:0] s_tdata;
    logic       s_tvalid;
    logic       s_tready;
    logic       s_tlast;
    logic [7:0] m_tdata;
    logic       m_tvalid;
    logic       m_tready;
    logic       m_tlast;
    logic       enable;
endinterface

package netsec_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class netsec_seq_item extends uvm_sequence_item;
        `uvm_object_utils(netsec_seq_item)
        rand byte unsigned pkt_bytes[$];
        constraint c_len { pkt_bytes.size() inside {[64:128]}; }
        function new(string name="netsec_seq_item");
            super.new(name);
        endfunction
    endclass

    class netsec_driver extends uvm_driver #(netsec_seq_item);
        `uvm_component_utils(netsec_driver)
        virtual netsec_if vif;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual netsec_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "no vif")
        endfunction
        task run_phase(uvm_phase phase);
            netsec_seq_item item;
            vif.s_tvalid <= 1'b0;
            vif.s_tlast  <= 1'b0;
            vif.m_tready <= 1'b1;
            vif.enable   <= 1'b1;
            @(posedge vif.rst_n);
            forever begin
                seq_item_port.get_next_item(item);
                foreach (item.pkt_bytes[i]) begin
                    @(posedge vif.clk);
                    vif.s_tvalid <= 1'b1;
                    vif.s_tdata  <= item.pkt_bytes[i];
                    vif.s_tlast  <= (i == item.pkt_bytes.size()-1);
                    do @(posedge vif.clk); while (!vif.s_tready);
                end
                @(posedge vif.clk);
                vif.s_tvalid <= 1'b0;
                vif.s_tlast  <= 1'b0;
                seq_item_port.item_done();
            end
        endtask
    endclass

    class netsec_sequencer extends uvm_sequencer #(netsec_seq_item);
        `uvm_component_utils(netsec_sequencer)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class netsec_smoke_seq extends uvm_sequence #(netsec_seq_item);
        `uvm_object_utils(netsec_smoke_seq)
        function new(string name="netsec_smoke_seq");
            super.new(name);
        endfunction
        task body();
            netsec_seq_item item;
            item = netsec_seq_item::type_id::create("item");
            start_item(item);
            // Minimal Ethernet broadcast + IPv4/TCP-ish pad
            item.pkt_bytes.delete();
            repeat (6) item.pkt_bytes.push_back(8'hff);
            repeat (6) item.pkt_bytes.push_back(8'h02);
            item.pkt_bytes.push_back(8'h08); item.pkt_bytes.push_back(8'h00);
            repeat (46) item.pkt_bytes.push_back(8'h00);
            finish_item(item);
        endtask
    endclass

    class netsec_env extends uvm_env;
        `uvm_component_utils(netsec_env)
        netsec_driver    drv;
        netsec_sequencer sqr;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            drv = netsec_driver::type_id::create("drv", this);
            sqr = netsec_sequencer::type_id::create("sqr", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    class netsec_smoke_test extends uvm_test;
        `uvm_component_utils(netsec_smoke_test)
        netsec_env env;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        function void build_phase(uvm_phase phase);
            env = netsec_env::type_id::create("env", this);
        endfunction
        task run_phase(uvm_phase phase);
            netsec_smoke_seq seq;
            phase.raise_objection(this);
            seq = netsec_smoke_seq::type_id::create("seq");
            seq.start(env.sqr);
            repeat (500) @(posedge env.drv.vif.clk);
            phase.drop_objection(this);
        endtask
    endclass
endpackage

module tb_netsec_uvm;
    import uvm_pkg::*;
    import netsec_uvm_pkg::*;

    logic clk, rst_n;
    initial begin clk = 0; forever #4 clk = ~clk; end
    initial begin rst_n = 0; repeat (10) @(posedge clk); rst_n = 1; end

    netsec_if vif(clk, rst_n);

    netsec_datapath dut (
        .clk(clk), .rst_n(rst_n), .enable(vif.enable),
        .s_tdata(vif.s_tdata), .s_tvalid(vif.s_tvalid),
        .s_tready(vif.s_tready), .s_tlast(vif.s_tlast),
        .m_tdata(vif.m_tdata), .m_tvalid(vif.m_tvalid),
        .m_tready(vif.m_tready), .m_tlast(vif.m_tlast),
        .mirror_pulse(), .last_action(),
        .stat_rx_frame(), .stat_tx_frame(), .stat_forward(),
        .stat_drop(), .stat_mirror(), .stat_dpi_hit(),
        .flow_update_valid(), .flow_update_state(),
        .dpi_pat0(32'h47455420), .dpi_pat1(32'h636d642e),
        .dpi_pat2(32'h53454c45), .dpi_pat3(32'h90909090),
        .aes_dp_en(1'b0), .aes_key(128'h0), .aes_dp_ct(), .aes_dp_done()
    );

    initial begin
        uvm_config_db#(virtual netsec_if)::set(null, "*", "vif", vif);
        run_test("netsec_smoke_test");
    end
endmodule
