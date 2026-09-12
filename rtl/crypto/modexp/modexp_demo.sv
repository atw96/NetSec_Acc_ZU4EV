// modexp_demo.sv
// 简化版模幂运算 Demo（32bit，Square-and-Multiply，非 Montgomery）。
// 明确声明：这是原理演示模块，不是可商用的 RSA 加速器，见 05_crypto_engine.md。
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

    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_e;
    state_e state;

    logic [WIDTH-1:0]   base_reg, mod_reg, result_reg;
    logic [WIDTH-1:0]   exp_reg;
    logic [2*WIDTH-1:0] mul_tmp;

    // 组合模乘（WIDTH bit）：真实工程中此处应替换为 Montgomery 模乘以避免长除法开销，
    // 当前用行为级 % 运算符描述功能，供仿真验证正确性使用。
    function automatic [WIDTH-1:0] modmul(input [WIDTH-1:0] a, input [WIDTH-1:0] b, input [WIDTH-1:0] m);
        logic [2*WIDTH-1:0] p;
        p = a * b;
        modmul = (m == 0) ? '0 : (p % m);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            done       <= 1'b0;
            result     <= '0;
            base_reg   <= '0;
            exp_reg    <= '0;
            mod_reg    <= '0;
            result_reg <= '0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        base_reg   <= (mod_in == 0) ? base_in : (base_in % mod_in);
                        exp_reg    <= exp_in;
                        mod_reg    <= mod_in;
                        result_reg <= (mod_in <= 1) ? '0 : {{(WIDTH-1){1'b0}}, 1'b1}; // result=1
                        state      <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (exp_reg == '0) begin
                        result <= result_reg;
                        done   <= 1'b1;
                        state  <= S_IDLE;
                    end else begin
                        if (exp_reg[0])
                            result_reg <= modmul(result_reg, base_reg, mod_reg);
                        base_reg <= modmul(base_reg, base_reg, mod_reg);
                        exp_reg  <= exp_reg >> 1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
