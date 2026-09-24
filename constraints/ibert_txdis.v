// Drive SFP TX_DISABLE low on the IBERT example (factory XDC omitted this pin).
// SOURCE: MANUAL PAGE44 — PACKAGE_PIN D12 LVCMOS33
`timescale 1ns / 1ps
module ibert_txdis (
    output wire sfp_tx_dis
);
    assign sfp_tx_dis = 1'b0;
endmodule
