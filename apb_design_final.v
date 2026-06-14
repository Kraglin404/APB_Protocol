//  APB MASTER 

module apb_master (
    input             P_clk,
    input             P_rst,
    input      [31:0] addr_i,
    input      [31:0] wdata_i,
    input             write_en_i,
    input             read_en_i,
    output reg [31:0] P_addr,
    output reg        P_sel,
    output reg        P_enable,
    output reg        P_write,
    output reg [31:0] P_wdata,
    input             P_ready,
    input      [31:0] P_rdata,
    input             P_slverr,
    output reg [31:0] rdata_o,
    output reg        done_o,
    output reg        error_o
);

    localparam IDLE   = 2'b00;
    localparam SETUP  = 2'b01;
    localparam ACCESS = 2'b10;

    reg [1:0] current_state, next_state;

    always @(posedge P_clk or posedge P_rst) begin
        if (P_rst) current_state <= IDLE;
        else       current_state <= next_state;
    end

    //  Next-state 
    always @(*) begin
        case (current_state)
            IDLE  : next_state = (write_en_i || read_en_i) ? SETUP : IDLE;
            SETUP : next_state = ACCESS;
            ACCESS: next_state = P_ready ? IDLE : ACCESS;  // wait-state loop
            default: next_state = IDLE;
        endcase
    end

    always @(posedge P_clk or posedge P_rst) begin
        if (P_rst) begin
            P_addr <= 0; P_sel <= 0; P_enable <= 0;
            P_write <= 0; P_wdata <= 0;
            rdata_o <= 0; done_o <= 0; error_o <= 0;
        end else begin
            case (next_state)

                IDLE: begin
                    P_sel    <= 0;
                    P_enable <= 0;
                    if (current_state == ACCESS && P_ready) begin
                        done_o  <= 1;
                        error_o <= P_slverr;           // capture slave error
                        if (!P_write) rdata_o <= P_rdata;
                    end else begin
                        done_o <= 0;
                    end
                end

                SETUP: begin
            
                    P_addr   <= addr_i;
                    P_write  <= write_en_i;
                    P_wdata  <= wdata_i;
                    P_sel    <= 1;
                    P_enable <= 0;
                    done_o   <= 0;
                    error_o  <= 0;   
                end

                ACCESS: begin
                    P_enable <= 1;
                end

            endcase
        end
    end

endmodule

//  SLAVE 1 – RAM  
module apb_ram (
    input        P_clk, P_rst,
    input [31:0] P_addr,
    input        P_sel, P_enable, P_write,
    input [31:0] P_wdata,
    output reg [31:0] P_rdata,
    output reg        P_ready,
    output reg        P_slverr
);

    reg [31:0] mem [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            mem[i] = 32'h0;
    end

    wire access = P_sel & P_enable;

    always @(posedge P_clk or posedge P_rst) begin
        if (P_rst) begin
            P_ready <= 0; P_slverr <= 0; P_rdata <= 32'h0;
        end else begin
            P_ready  <= 0;
            P_slverr <= 0;
            P_rdata  <= 32'h0;          
            if (access) begin
                P_ready <= 1;
                if (P_addr > 31) begin 
                    P_slverr <= 1;
                    P_rdata  <= 32'h0;  
                end else if (P_write)
                    mem[P_addr[4:0]] <= P_wdata;
                else
                    P_rdata <= mem[P_addr[4:0]];
            end
        end
    end
endmodule


//  SLAVE 1b – SLOW RAM  (NEW: demonstrates wait-state / clock stretching)
//  Responds after 3 ACCESS cycles  (P_ready held low for 2 extra cycles)

module apb_ram_slow (
    input        P_clk, P_rst,
    input [31:0] P_addr,
    input        P_sel, P_enable, P_write,
    input [31:0] P_wdata,
    output reg [31:0] P_rdata,
    output reg        P_ready,
    output reg        P_slverr
);
    reg [31:0] mem [0:31];
    reg [1:0]  wait_cnt;   

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) mem[i] = 32'h0;
        wait_cnt = 0;
    end

    wire access = P_sel & P_enable;

    always @(posedge P_clk or posedge P_rst) begin
        if (P_rst) begin
            P_ready <= 0; P_slverr <= 0; P_rdata <= 32'h0; wait_cnt <= 0;
        end else begin
            P_ready  <= 0;
            P_slverr <= 0;
            P_rdata  <= 32'h0;         

            if (access) begin
                if (wait_cnt < 2) begin
              
                    wait_cnt <= wait_cnt + 1;
                end else begin
                   
                    P_ready  <= 1;
                    wait_cnt <= 0;
                    if (P_addr > 31) begin
                        P_slverr <= 1;
                        P_rdata  <= 32'h0;  // defined value even on error
                    end else if (P_write)
                        mem[P_addr[4:0]] <= P_wdata;
                    else
                        P_rdata <= mem[P_addr[4:0]];
                end
            end else begin
                wait_cnt <= 0;   // reset counter if deselected
            end
        end
    end
endmodule

//  SLAVE 2 – TIMER  

module apb_timer (
    input        P_clk, P_rst,
    input [31:0] P_addr,
    input        P_sel, P_enable, P_write,
    input [31:0] P_wdata,
    output reg [31:0] P_rdata,
    output reg        P_ready,
    output reg        P_slverr
);
    reg [31:0] timer;
    wire access = P_sel & P_enable;

    wire [31:0] offset = P_addr - 32;

    always @(posedge P_clk or posedge P_rst) begin
        if (P_rst) begin
            timer <= 0; P_ready <= 0; P_slverr <= 0;
        end else begin
            P_ready  <= 0;
            P_slverr <= 0;
            P_rdata  <= 32'h0;          
            if (access) begin
                P_ready <= 1;
        
                if (offset > 8) begin
                    P_slverr <= 1;
                    P_rdata  <= 32'h0;  
                end else begin
                    if (P_write) timer   <= P_wdata;
                    else         P_rdata <= timer;
                end
            end
        end
    end
endmodule

//  SLAVE 3 – GPIO  

module apb_gpio (
    input        P_clk, P_rst,
    input [31:0] P_addr,
    input        P_sel, P_enable, P_write,
    input [31:0] P_wdata,
    output reg [31:0] P_rdata,
    output reg        P_ready,
    output reg        P_slverr
);
    reg [31:0] gpio_reg;
    wire access = P_sel & P_enable;

    wire [31:0] offset = P_addr - 64;

    always @(posedge P_clk or posedge P_rst) begin
        if (P_rst) begin
            gpio_reg <= 0; P_ready <= 0; P_slverr <= 0;
        end else begin
            P_ready  <= 0;
            P_slverr <= 0;
            P_rdata  <= 32'h0;          
            if (access) begin
                P_ready <= 1;
                if (offset > 8) begin
                    P_slverr <= 1;
                    P_rdata  <= 32'h0; 
                end else begin
                    if (P_write) gpio_reg <= P_wdata;
                    else         P_rdata  <= gpio_reg;
                end
            end
        end
    end
endmodule

//  INTERCONNECT / TOP  

module AMBA_APB_SYSTEM (
    input        P_clk, P_rst,
    input [31:0] P_addr,
    input        P_sel, P_enable, P_write,
    input [31:0] P_wdata,
    output [31:0] P_rdata,
    output        P_ready,
    output        P_slverr
);
    wire sel1, sel2, sel3, sel4;
    wire [31:0] rdata1, rdata2, rdata3, rdata4;
    wire ready1, ready2, ready3, ready4;
    wire err1,   err2,   err3,   err4;

    assign sel1 = P_sel && (P_addr < 32);
    assign sel2 = P_sel && (P_addr >= 32  && P_addr < 64);
    assign sel3 = P_sel && (P_addr >= 64  && P_addr < 96);
    assign sel4 = P_sel && (P_addr >= 96  && P_addr < 128);

    apb_ram RAM (
        P_clk, P_rst, P_addr, sel1, P_enable, P_write, P_wdata,
        rdata1, ready1, err1
    );
    apb_timer TIMER (
        P_clk, P_rst, P_addr, sel2, P_enable, P_write, P_wdata,
        rdata2, ready2, err2
    );
    apb_gpio GPIO (
        P_clk, P_rst, P_addr, sel3, P_enable, P_write, P_wdata,
        rdata3, ready3, err3
    );
    apb_ram_slow SLOW_RAM (
        P_clk, P_rst, P_addr, sel4, P_enable, P_write, P_wdata,
        rdata4, ready4, err4
    );

    assign P_rdata  = sel1 ? rdata1 :
                      sel2 ? rdata2 :
                      sel3 ? rdata3 :
                      sel4 ? rdata4 : 32'h0;

    assign P_ready  = sel1 ? ready1 : sel2 ? ready2 :
                      sel3 ? ready3 : sel4 ? ready4 : 1'b1;
                     

    assign P_slverr = sel1 ? err1 : sel2 ? err2 :
                      sel3 ? err3 : sel4 ? err4 : 1'b1;
                     
endmodule

//  WRAPPER
module apb_subsystem_top (
    input         clk, rst,
    input  [31:0] addr_i, wdata_i,
    input         write_en_i, read_en_i,
    output [31:0] rdata_o,
    output        done_o, error_o
);
    wire [31:0] p_addr, p_wdata, p_rdata;
    wire p_sel, p_enable, p_write, p_ready, p_slverr;

    apb_master Master_Unit (
        .P_clk(clk),       .P_rst(rst),
        .addr_i(addr_i),   .wdata_i(wdata_i),
        .write_en_i(write_en_i), .read_en_i(read_en_i),
        .P_addr(p_addr),   .P_sel(p_sel),
        .P_enable(p_enable),.P_write(p_write),
        .P_wdata(p_wdata), .P_ready(p_ready),
        .P_rdata(p_rdata), .P_slverr(p_slverr),
        .rdata_o(rdata_o), .done_o(done_o), .error_o(error_o)
    );

    AMBA_APB_SYSTEM Slave_Subsystem (
        .P_clk(clk),       .P_rst(rst),
        .P_addr(p_addr),   .P_sel(p_sel),
        .P_enable(p_enable),.P_write(p_write),
        .P_wdata(p_wdata), .P_rdata(p_rdata),
        .P_ready(p_ready), .P_slverr(p_slverr)
    );
endmodule