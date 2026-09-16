// modexp_demo.sv
// 简化版模幂运算 Demo（32bit，Square-and-Multiply，非 Montgomery）。
// 模乘用寄存乘法 + 多周期恢复余数，避免综合出单周期 64bit `%`。
// 明确声明：原理演示，不是可商用 RSA 加速器。
module u_modexp_demo #(
    parameter WIDTH = 32
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic [WIDTH-1:0]   base_in,
    input  logic [WIDTH-1:0]   exp_in,
    input  logic [WIDTH-1:0]   mod_in,
    output logic               done,
    output logic [WIDTH-1:0]   result
);

    localparam int PROD_W = 2 * WIDTH;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_RED,
        ST_LOOP,
        ST_PROD,
        ST_DIV
    } st_e;

    st_e                st, st_ret;
    logic [WIDTH-1:0]   base_r, exp_r, mod_r, acc_r;
    logic [PROD_W-1:0]  prod;
    logic [WIDTH:0]     rem;
    logic [WIDTH:0]     sh;
    logic [6:0]         div_i;
    logic               mul_to_acc; // 1: write rem to acc; 0: write rem to base
    logic               do_sqr_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st          <= ST_IDLE;
            st_ret      <= ST_IDLE;
            done        <= 1'b0;
            result      <= '0;
            base_r      <= '0;
            exp_r       <= '0;
            mod_r       <= '0;
            acc_r       <= '0;
            prod        <= '0;
            rem         <= '0;
            div_i       <= '0;
            mul_to_acc  <= 1'b0;
            do_sqr_next <= 1'b0;
        end else begin
            done <= 1'b0;
            case (st)
                ST_IDLE: begin
                    if (start) begin
                        mod_r       <= mod_in;
                        exp_r       <= exp_in;
                        acc_r       <= (mod_in <= 1) ? '0 : {{(WIDTH-1){1'b0}}, 1'b1};
                        prod        <= {{WIDTH{1'b0}}, base_in};
                        rem         <= '0;
                        div_i       <= WIDTH[6:0];
                        mul_to_acc  <= 1'b0;
                        do_sqr_next <= 1'b0;
                        if (mod_in <= 1) begin
                            result <= '0;
                            done   <= 1'b1;
                            st     <= ST_IDLE;
                        end else begin
                            st <= ST_RED;
                        end
                    end
                end
                // base_in % mod  : WIDTH 拍恢复余数
                ST_RED: begin
                    if (div_i == 0) begin
                        base_r <= rem[WIDTH-1:0];
                        st     <= ST_LOOP;
                    end else begin
                        sh = {rem[WIDTH-1:0], prod[div_i-1]};
                        if (sh >= {1'b0, mod_r})
                            rem <= sh - {1'b0, mod_r};
                        else
                            rem <= sh;
                        div_i <= div_i - 1'b1;
                    end
                end
                ST_LOOP: begin
                    if (exp_r == '0) begin
                        result <= acc_r;
                        done   <= 1'b1;
                        st     <= ST_IDLE;
                    end else if (exp_r[0]) begin
                        mul_to_acc  <= 1'b1;
                        do_sqr_next <= 1'b1;
                        st_ret      <= ST_LOOP;
                        st          <= ST_PROD;
                    end else begin
                        mul_to_acc  <= 1'b0;
                        do_sqr_next <= 1'b0;
                        st_ret      <= ST_LOOP;
                        st          <= ST_PROD;
                    end
                end
                ST_PROD: begin
                    if (mul_to_acc)
                        prod <= acc_r * base_r;
                    else
                        prod <= base_r * base_r;
                    rem   <= '0;
                    div_i <= PROD_W[6:0];
                    st    <= ST_DIV;
                end
                ST_DIV: begin
                    if (div_i == 0) begin
                        if (mul_to_acc)
                            acc_r <= rem[WIDTH-1:0];
                        else begin
                            base_r <= rem[WIDTH-1:0];
                            exp_r  <= exp_r >> 1;
                        end
                        if (mul_to_acc && do_sqr_next) begin
                            mul_to_acc  <= 1'b0;
                            do_sqr_next <= 1'b0;
                            st          <= ST_PROD;
                        end else begin
                            st <= st_ret;
                        end
                    end else begin
                        sh = {rem[WIDTH-1:0], prod[div_i-1]};
                        if (sh >= {1'b0, mod_r})
                            rem <= sh - {1'b0, mod_r};
                        else
                            rem <= sh;
                        div_i <= div_i - 1'b1;
                    end
                end
                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
