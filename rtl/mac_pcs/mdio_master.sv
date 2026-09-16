// mdio_master.sv — IEEE 802.3 Clause-22 MDIO master
// axi_clk = 100 MHz -> MDC = 2.5 MHz (divide by 40)
`timescale 1ns / 1ps

module mdio_master #(
    parameter int CLK_DIV_HALF = 20  // half-period counts @ 100 MHz
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start,
    input  logic        we,           // 1 = write, 0 = read
    input  logic [4:0]  phy_addr,
    input  logic [4:0]  reg_addr,
    input  logic [15:0] wdata,
    output logic [15:0] rdata,
    output logic        busy,
    output logic        done,         // 1-cycle pulse

    output logic        mdc,
    output logic        mdio_o,
    output logic        mdio_t,       // 1 = tristate (input)
    input  logic        mdio_i
);

    typedef enum logic [1:0] { ST_IDLE, ST_RUN, ST_DONE } state_t;
    state_t state;

    logic [5:0]  bit_idx;     // 0..63
    logic [6:0]  div_cnt;
    logic        mdc_q;
    logic        we_r;
    logic [63:0] shreg;
    logic [15:0] racc;
    logic        sample;

    assign mdc  = (state == ST_RUN) ? mdc_q : 1'b0;
    assign busy = (state != ST_IDLE);

    // Drive MDIO only on preamble/ST/OP/PHY/REG and write TA+DATA (bits 63..18 of write).
    // Read: drive bits 63..18 (through first TA), then release.
    wire drive_en = we_r ? 1'b1 : (bit_idx >= 6'd18);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= ST_IDLE;
            bit_idx <= '0;
            div_cnt <= '0;
            mdc_q   <= 1'b0;
            we_r    <= 1'b0;
            shreg   <= '0;
            rdata   <= '0;
            racc    <= '0;
            done    <= 1'b0;
            mdio_o  <= 1'b1;
            mdio_t  <= 1'b1;
            sample  <= 1'b0;
        end else begin
            done   <= 1'b0;
            sample <= 1'b0;

            unique case (state)
                ST_IDLE: begin
                    mdc_q   <= 1'b0;
                    mdio_t  <= 1'b1;
                    mdio_o  <= 1'b1;
                    div_cnt <= '0;
                    bit_idx <= 6'd63;
                    if (start) begin
                        we_r  <= we;
                        // {preamble[31:0]=1, ST=01, OP, PHYAD, REGAD, TA, DATA}
                        if (we) begin
                            shreg <= {32'hFFFF_FFFF, 2'b01, 2'b01, phy_addr, reg_addr, 2'b10, wdata};
                        end else begin
                            shreg <= {32'hFFFF_FFFF, 2'b01, 2'b10, phy_addr, reg_addr, 2'b00, 16'h0000};
                        end
                        racc  <= '0;
                        state <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (div_cnt == CLK_DIV_HALF[6:0] - 7'd1) begin
                        div_cnt <= '0;
                        mdc_q   <= ~mdc_q;
                        if (!mdc_q) begin
                            // Falling edge: present next bit
                            mdio_o <= shreg[bit_idx];
                            mdio_t <= ~drive_en;
                        end else begin
                            // Rising edge: sample
                            sample <= 1'b1;
                            if (!we_r && (bit_idx <= 6'd15))
                                racc <= {racc[14:0], mdio_i};
                            if (bit_idx == 6'd0)
                                state <= ST_DONE;
                            else
                                bit_idx <= bit_idx - 1'b1;
                        end
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                ST_DONE: begin
                    mdc_q  <= 1'b0;
                    mdio_t <= 1'b1;
                    if (!we_r)
                        rdata <= racc;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
