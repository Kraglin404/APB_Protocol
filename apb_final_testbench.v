//  TESTBENCH  

module tb;

    reg P_clk, P_rst;
    reg [31:0] addr_i, wdata_i;
    reg write_en_i, read_en_i;
    wire [31:0] rdata_o;
    wire done_o, error_o;

    apb_subsystem_top dut (
        .clk(P_clk), .rst(P_rst),
        .addr_i(addr_i), .wdata_i(wdata_i),
        .write_en_i(write_en_i), .read_en_i(read_en_i),
        .rdata_o(rdata_o), .done_o(done_o), .error_o(error_o)
    );

    always #5 P_clk = ~P_clk;

    task initialization;
    begin
        P_clk = 0; P_rst = 0;
        addr_i = 0; wdata_i = 0;
        write_en_i = 0; read_en_i = 0;
    end
    endtask

    task reset;
    begin
        @(posedge P_clk); P_rst = 1;
        @(posedge P_clk); P_rst = 0;
    end
    endtask

    task system_write;
        input [31:0] addr, data;
    begin
        @(posedge P_clk);
        addr_i = addr; wdata_i = data; write_en_i = 1;
        @(posedge P_clk);
        write_en_i = 0;
        wait(done_o);
        $display("[WRITE] Addr=%0d  Data=%0d  Error=%b", addr, data, error_o);
        @(posedge P_clk);
    end
    endtask

    task system_read;
        input [31:0] addr;
    begin
        @(posedge P_clk);
        addr_i = addr; read_en_i = 1;
        @(posedge P_clk);
        read_en_i = 0;
        wait(done_o);
        $display("[READ ] Addr=%0d  Data=%0d  Error=%b", addr, rdata_o, error_o);
        @(posedge P_clk);
    end
    endtask

    // Simulation
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb);

        initialization;
        reset;

        //  TEST 1: Fast RAM (addr 0-31) 

        $display("\n=== TEST 1: Fast RAM (1-cycle ready) ===");
        system_write(10, 111);
        system_read(10);          
        system_read(5);            

        // TEST 2: Timer (addr 32-63)
        $display("\n=== TEST 2: Timer ===");
        system_write(40, 555);
        system_read(40);           

        //  TEST 3: GPIO (addr 64-95)
        $display("\n=== TEST 3: GPIO ===");
        system_write(80, 999);
        system_read(80);           

        // TEST 4: Slow RAM – wait-state / clock stretching
   
        $display("\n=== TEST 4: Slow RAM – wait-state demo (addr 96-127) ===");
        system_write(100, 7777);
        system_read(100);          

        // TEST 5: SLVERR – unmapped address (128+) 
        $display("\n=== TEST 5: SLVERR – unmapped address 200 ===");
        system_write(200, 123);    
        system_read(200);          

        // TEST 6: SLVERR – RAM out-of-bounds within mapped window
        $display("\n=== TEST 6: SLVERR – Timer invalid offset (addr 60) ===");
      
        system_write(60, 456);     
        system_read(60);           

        // TEST 7: GPIO invalid offset 
        $display("\n=== TEST 7: SLVERR – GPIO invalid offset (addr 90) ===");
        // offset = 90-64 = 26 > 8 → GPIO raises SLVERR
        system_write(90, 789);
        system_read(90);

        // TEST 8: Back-to-back verify (no stale error) 
        $display("\n=== TEST 8: Back-to-back after error – error must clear ===");
        system_write(10, 42);      
        system_read(10);           

        #50;
        $finish;
    end

endmodule
