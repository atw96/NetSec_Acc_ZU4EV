# 报文级 UVM 验证环境（骨架，未在本仓库沙箱中编译验证）

**重要说明**：Icarus Verilog（本仓库沙箱唯一可用的开源仿真器）默认不包含 UVM 库，
第三方移植版本（如 uvm-verilog）兼容性有限。以下代码为**可读的类结构骨架**，
用于面试中展示验证方法学设计能力，建议在具备 QuestaSim / VCS / Xcelium
授权的环境中实际编译运行，作为进一步加分项。

设计思路见 `docs/verification_plan.md`。

## 目录规划

```
tb/uvm_env/
├── netsec_pkg.sv          # UVM 环境包，包含以下所有 class
├── netsec_seq_item.sv      # Sequence Item：一个报文(byte queue) + 元数据
├── netsec_driver.sv        # Driver：将 seq_item 逐字节驱动到 DUT
├── netsec_monitor.sv       # Monitor：采集 DUT 输出(action/hit_vector/checksum等)
├── netsec_scoreboard.sv    # Scoreboard：并行运行 Python 黄金模型逻辑的等价 SV 参考实现，
│                           # 或通过 DPI-C 直接调用 python_model/*.py 比对（进阶写法）
├── netsec_coverage.sv      # Functional Coverage：五元组协议分布/DPI命中/决策路径
├── netsec_env.sv           # Env：组装 agent + scoreboard + coverage
└── netsec_test_base.sv     # 基础 Test，从 python_model/pcap_gen.py 生成的 pcap 加载报文
```

## 关键代码骨架（示例，非完整可编译代码）

```systemverilog
class netsec_seq_item extends uvm_sequence_item;
    `uvm_object_utils(netsec_seq_item)
    rand byte unsigned pkt_bytes[$];  // 一个完整报文的字节队列
    bit [3:0] expected_dpi_hit_vector; // 从 Python 黄金模型预先计算好，随 pcap 一起加载
    function new(string name = "netsec_seq_item");
        super.new(name);
    endfunction
endclass

class netsec_driver extends uvm_driver #(netsec_seq_item);
    `uvm_component_utils(netsec_driver)
    virtual netsec_if vif; // 需自定义 interface 绑定 DUT 的 s_valid/s_data/s_last
    task run_phase(uvm_phase phase);
        netsec_seq_item item;
        forever begin
            seq_item_port.get_next_item(item);
            foreach (item.pkt_bytes[i]) begin
                @(posedge vif.clk);
                vif.s_valid <= 1'b1;
                vif.s_data  <= item.pkt_bytes[i];
                vif.s_last  <= (i == item.pkt_bytes.size()-1);
            end
            @(posedge vif.clk);
            vif.s_valid <= 1'b0;
            seq_item_port.item_done();
        end
    endtask
endclass

class netsec_scoreboard extends uvm_component;
    `uvm_component_utils(netsec_scoreboard)
    uvm_analysis_imp #(netsec_seq_item, netsec_scoreboard) item_export;
    function void write(netsec_seq_item item);
        // 与 python_model 预先算好的 expected_dpi_hit_vector 等字段比对，
        // 不一致则 `uvm_error("SCOREBOARD", ...)`
    endfunction
endclass
```

## 后续落地步骤（供本地环境执行）

1. 在具备 UVM 授权的仿真器中，先跑通一个最小 sanity test（1 个报文，检查 driver/monitor 能正常握手）。
2. 用 `python_model/pcap_gen.py` 生成的 pcap，配合 Python 脚本预先计算好每个报文的
   期望 DPI 命中向量/校验和/流表状态迁移，导出为一个 `.mem`/`.json` 文件供 SV 端 `$readmem`
   或 DPI-C 读取，Scoreboard 据此比对。
3. 逐步补全 Functional Coverage，目标覆盖率见 `docs/verification_plan.md`。
