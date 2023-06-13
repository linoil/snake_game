`timescale 1ns / 1ps
module lab10(
    input  clk,
    input  reset_n,
    input  [3:0] usr_btn,
    output [3:0] usr_led,
    
    // VGA specific I/O ports
    output VGA_HSYNC,
    output VGA_VSYNC,
    output [3:0] VGA_RED,
    output [3:0] VGA_GREEN,
    output [3:0] VGA_BLUE
    );

localparam[2:0] S_MAIN_INIT = 3'b000, S_MAIN_LEVEL1 = 3'b001, S_MAIN_UPUP = 3'b010
                ,S_MAIN_LEVEL2 = 3'b011, S_MAIN_DEAD = 3'b100;
reg [2:0] P, P_next;
reg [4:0] snake_length; // initialize 5
reg [4:0] score;
reg [4:0] pre_score;
reg [1:0] level;
//variables with only background
wire [16:0] sram_addr_bg;
wire [11:0] data_in;
wire [11:0] data_out_bg;
wire        sram_we, sram_en;
wire vga_clk;        
wire video_on;       
wire pixel_tick; 
wire [9:0] pixel_x;
wire [9:0] pixel_y; 
reg  [11:0] rgb_reg;
reg  [11:0] rgb_next; 
reg  [17:0] pixel_addr_bg;
localparam VBUF_W = 320;
localparam VBUF_H = 240; 
reg dead;
//block variables
reg [9:0] block_x[0:24];
reg [9:0] block_y[0:24];
wire [24:0] block_region;
reg [24:0] block_enable;
reg [17:0] pixel_addr_block;
wire [11:0] data_out_block;
reg touch_block;
reg pre_touch_block;
localparam BLOCK_SIZE = 32;
reg [17:0] block_addr;

//point
reg [9:0] point_x[0:9];
reg [9:0] point_y[0:9];
wire [9:0] point_region;
reg [9:0] point_enable;
wire [16:0] sram_addr_point;
wire [11:0] data_in;
wire [11:0] data_out_point;
reg [17:0] pixel_addr_point;
reg [17:0] point_addr;
//reg eat_point;

// snake(head)
reg [63:0] snake_clk;
reg [1:0] direction; // 0 right, 1 left, 2 up, 3 down
localparam MAX_LEN = 20;
reg [9:0] pos_x[0:MAX_LEN-1];// the x position of the right edge
reg [9:0] pos_y[0:MAX_LEN-1];
wire [MAX_LEN-1:0] snake_region;
reg [MAX_LEN-1:0] snake_enable;
wire [16:0] sram_addr_head, data_out_head;
wire [11:0] data_out_head, data_out_body;
reg [17:0] pixel_addr_head, pixel_addr_body;
reg [17:0] snake_h_b[0:4];

wire [16:0] sram_addr_num0, sram_addr_num5;
wire [11:0] data_out_num0, data_out_num5;
reg [17:0] pixel_addr_num0, pixel_addr_num5;
reg [17:0] num_addr[0:9];
wire num_region;

wire [3:0] btn;

initial begin
  // head
  snake_h_b[2] = 18'b0; // up
  snake_h_b[3] = BLOCK_SIZE*BLOCK_SIZE*1; // down
  snake_h_b[1] = BLOCK_SIZE*BLOCK_SIZE*2; // left
  snake_h_b[0] = BLOCK_SIZE*BLOCK_SIZE*3; // right
  // body
  snake_h_b[4] = BLOCK_SIZE*BLOCK_SIZE*4;
  
  block_addr = 18'b0;
  point_addr = BLOCK_SIZE*BLOCK_SIZE;
  num_addr[0] = 18'b0;
  num_addr[1] = BLOCK_SIZE*BLOCK_SIZE*4*1;
  num_addr[2] = BLOCK_SIZE*BLOCK_SIZE*4*2;
  num_addr[3] = BLOCK_SIZE*BLOCK_SIZE*4*3;
  num_addr[4] = BLOCK_SIZE*BLOCK_SIZE*4*4;
  num_addr[5] = 18'b0;
  num_addr[6] = BLOCK_SIZE*BLOCK_SIZE*4*1;
  num_addr[7] = BLOCK_SIZE*BLOCK_SIZE*4*2;
  num_addr[8] = BLOCK_SIZE*BLOCK_SIZE*4*3;
  num_addr[9] = BLOCK_SIZE*BLOCK_SIZE*4*4;
end

vga_sync vs0(
  .clk(vga_clk), .reset(~reset_n), .oHS(VGA_HSYNC), .oVS(VGA_VSYNC),
  .visible(video_on), .p_tick(pixel_tick),
  .pixel_x(pixel_x), .pixel_y(pixel_y)
);
clk_divider#(2) clk_divider0(
  .clk(clk),
  .reset(~reset_n),
  .clk_out(vga_clk)
);
debounce db0(
    .clk(clk),
    .btn_input(usr_btn[0]),
    .btn_output(btn[0])
    );
debounce db1(
    .clk(clk),
    .btn_input(usr_btn[1]),
    .btn_output(btn[1])
    );
debounce db2(
    .clk(clk),
    .btn_input(usr_btn[2]),
    .btn_output(btn[2])
    );
debounce db3(
    .clk(clk),
    .btn_input(usr_btn[3]),
    .btn_output(btn[3])
    );

sram #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(VBUF_W*VBUF_H), .FILE("background.mem"))
  ram_b (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_bg), .data_i(data_in), .data_o(data_out_bg));
sram #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(BLOCK_SIZE*BLOCK_SIZE*2), .FILE("block_point.mem"))
  ram_block (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_block), .data_i(data_in), .data_o(data_out_block));          
sram #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(BLOCK_SIZE*BLOCK_SIZE*2), .FILE("block_point.mem"))
  ram_point (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_point), .data_i(data_in), .data_o(data_out_point));  
sram #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(BLOCK_SIZE*BLOCK_SIZE*5), .FILE("snake_head_udlr_body.mem"))
  ram_head (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_head), .data_i(data_in), .data_o(data_out_head));  
sram #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(BLOCK_SIZE*BLOCK_SIZE*5), .FILE("snake_head_udlr_body.mem"))
  ram_body (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_body), .data_i(data_in), .data_o(data_out_body));
sram #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(BLOCK_SIZE*BLOCK_SIZE*4*5), .FILE("0to4.mem"))
  ram_num04 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_num0), .data_i(data_in), .data_o(data_out_num0));
sram #(.DATA_WIDTH(12), .ADDR_WIDTH(18), .RAM_SIZE(BLOCK_SIZE*BLOCK_SIZE*4*5), .FILE("5to9.mem"))
  ram_num59 (.clk(clk), .we(sram_we), .en(sram_en),
          .addr(sram_addr_num5), .data_i(data_in), .data_o(data_out_num5));

assign sram_we = usr_led[3];
assign sram_en = 1;  
assign sram_addr_bg = pixel_addr_bg;
assign data_in = 12'h000; 
//block
assign sram_addr_block = pixel_addr_block;
//point
assign sram_addr_point = pixel_addr_point;
// head
assign sram_addr_head = pixel_addr_head;
// body
assign sram_addr_body = pixel_addr_body;
assign sram_addr_num0 = pixel_addr_num0;
assign sram_addr_num1 = pixel_addr_num5;

// VGA color pixel generator
assign {VGA_RED, VGA_GREEN, VGA_BLUE} = rgb_reg;

always @(posedge clk) begin
  if (pixel_tick) rgb_reg <= rgb_next;
end

always @(*) begin
  if (~video_on)
    rgb_next = 12'h000; // Synchronization period, must set RGB values to zero.
  else if (num_region) begin
    if((score>=0 && score<5) && data_out_num0 != 12'hfff) rgb_next <= data_out_num0; 
    else if(score<=9 && data_out_num5 != 12'hfff) rgb_next <= data_out_num5; 
  end
  else if (snake_region[0]) rgb_next <= data_out_head;
  else if (snake_region[1]||snake_region[2]||snake_region[3]||snake_region[4]||snake_region[5]||snake_region[6]||snake_region[7]||snake_region[8]||snake_region[9]||snake_region[10]
         ||snake_region[11]||snake_region[12]||snake_region[13]||snake_region[14]||snake_region[15]||snake_region[16]||snake_region[17]||snake_region[18]||snake_region[19]) rgb_next <= data_out_body;
  else if (block_region[0]||block_region[1]||block_region[2]||block_region[3]||block_region[4]
            ||block_region[5]||block_region[6]||block_region[7]||block_region[8]||block_region[9]) rgb_next <= data_out_block;
  else if (data_out_point  != 12'h0f0 && ((point_region[0] && point_enable[0])||(point_region[1] && point_enable[1])||(point_region[2] && point_enable[2])||(point_region[3] && point_enable[3])||(point_region[4] && point_enable[4]))) rgb_next <= data_out_point;
  else rgb_next = data_out_bg;
end

always @(posedge clk) begin
    if(~reset_n) P <= S_MAIN_INIT;
    else P <= P_next;
end
always @(posedge clk) begin
    case(P)
        S_MAIN_INIT:
            if(btn[0] == 1) P_next <= S_MAIN_LEVEL1;
            else P_next <= S_MAIN_INIT;
        S_MAIN_LEVEL1:
            if(score < 0) P_next <= S_MAIN_DEAD;
            else P_next <= S_MAIN_LEVEL1;
        S_MAIN_DEAD:
            if(btn[0] == 1) P_next = S_MAIN_LEVEL1;
            else P_next = S_MAIN_DEAD;
        /*S_MAIN_INIT:
            if(btn[0] == 1) P_next <= S_MAIN_LEVEL1;
            else P_next <= S_MAIN_INIT;
        S_MAIN_LEVEL1:
            if(score == 5) P_next <= S_MAIN_UPUP;
            else if(score == -1) P_next <= S_MAIN_DEAD;
            else P_next <= S_MAIN_LEVEL1;
        S_MAIN_UPUP: //LEVEL switching
            if(btn[0]==1) P_next <= S_MAIN_LEVEL2; // ##
            else P_next <= S_MAIN_UPUP;
        S_MAIN_LEVEL2:
            if(score == 9) P_next <= S_MAIN_INIT;
            else if(score == -1) P_next <= S_MAIN_DEAD;
            else P_next = S_MAIN_LEVEL2;
        S_MAIN_DEAD:
            if(btn[0] == 1 && level==0) P_next = S_MAIN_LEVEL1;
            else if(btn[0] == 1 && level==1) P_next = S_MAIN_LEVEL2;
            else P_next = S_MAIN_DEAD;*/
        default: P_next <= S_MAIN_INIT;
    endcase
end

//"direction": 0 right, 1 left, 2 up, 3 down
always@(posedge clk) begin
  if (~reset_n || P==S_MAIN_INIT || ( P_next == S_MAIN_LEVEL1 && P!=S_MAIN_LEVEL1)) direction <= 2'b00;
  else begin
    if(btn[0] == 1)direction <= 2'b00; // right
    else if(btn[1] == 1)direction <= 2'b01; // left
    else if(btn[2] == 1)direction <= 2'b10; // up
    else if(btn[3] == 1)direction <= 2'b11; // down
  end

  if ((pos_x[0]>=VBUF_W*2-1) && (pos_y[0]<=BLOCK_SIZE-1)) begin// right-top
    if (direction == 2'b00)
      direction <= 2'b11;
    else if (direction == 2'b10)
      direction <= 2'b01;
  end
  else if ((pos_x[0]>=VBUF_W*2-1) && (pos_y[0]>=VBUF_H*2-1)) begin // right-bottom
    if (direction == 2'b11) // up to down
      direction <= 2'b01;
    else if (direction == 2'b00) // left to right
      direction <= 2'b10;
  end
  else if ((pos_x[0]<=BLOCK_SIZE-1) && (pos_y[0]<=BLOCK_SIZE-1)) begin // left-top
    if (direction == 2'b01)
      direction <= 2'b11;
    else if (direction == 2'b10)
      direction <= 2'b00;
  end
  else if ((pos_x[0]<=BLOCK_SIZE-1) && (pos_y[0]>=VBUF_H*2-1)) begin // left-bottom
    if (direction == 2'b11) // up to down
      direction <= 2'b00;
    else if (direction == 2'b01) // right to left
      direction <= 2'b10;
  end
  else if ((pos_y[0]<=BLOCK_SIZE-1) && direction==2'b10) direction <= 2'b00; // top
  else if ((pos_y[0]>=VBUF_H*2-1) && direction==2'b11) direction <= 2'b00; // bottom
  else if ((pos_x[0]<=BLOCK_SIZE-1) && direction==2'b01) direction <= 2'b11; // left
  else if ((pos_x[0]>=VBUF_W*2-1) && direction==2'b00) direction <= 2'b11; // right
end

// "snake_clk"
always@(posedge clk) begin
  if (~reset_n || P==S_MAIN_INIT ||( P_next == S_MAIN_LEVEL1 && P!=S_MAIN_LEVEL1) || ( P_next == S_MAIN_LEVEL2 && P!=S_MAIN_LEVEL2)) begin
    snake_clk <= 0;
  end
  else if(snake_clk > 50000000)  begin
    snake_clk <= 1;
  end
  else begin
    snake_clk <= snake_clk +1;
  end
end

// pos_x and pos_y
integer i, j, k;
always@ (posedge clk) begin
  if(~reset_n || P==S_MAIN_INIT ||( P_next == S_MAIN_LEVEL1 && P!=S_MAIN_LEVEL1) ||( P_next == S_MAIN_LEVEL2 && P!=S_MAIN_LEVEL2)) begin
    for (j=0; j<15; j=j+1)  begin //## j
      pos_x[j] <= 480 - BLOCK_SIZE*j-1;
      pos_y[j] <= 32-1;
    end
    for (k=15; k<MAX_LEN; k=k+1)  begin //## j
      pos_x[k] <= 32-1;
      pos_y[k] <= 31+BLOCK_SIZE*(k-15);
    end
  end
  else if(touch_block) begin
    pos_x[0] <= pos_x[0];
    pos_y[0] <= pos_y[0];
  end
  else if((P_next == S_MAIN_DEAD) || P == S_MAIN_UPUP) begin
    pos_x[0] <= pos_x[0];
    pos_y[0] <= pos_y[0];
  end
  else if (snake_clk == 50000000) begin
    for(i=1; i<MAX_LEN; i=i+1) begin
      pos_x[i] <= pos_x[i-1];
      pos_y[i] <= pos_y[i-1];
    end
    case(direction)
      2'b00: begin
        pos_x[0] <= pos_x[0]+BLOCK_SIZE;
        pos_y[0] <= pos_y[0];
      end
      2'b01: begin
        pos_x[0] <= pos_x[0]-BLOCK_SIZE;
        pos_y[0] <= pos_y[0];
      end
      2'b10: begin
        pos_x[0] <= pos_x[0];
        pos_y[0] <= pos_y[0]-BLOCK_SIZE;
      end
      2'b11: begin
        pos_x[0] <= pos_x[0];
        pos_y[0] <= pos_y[0]+BLOCK_SIZE;
      end
    endcase
  end
end

integer idx_t_0, idx_t_1, idx_t_2, idx_t_3;
always@ (posedge clk) begin
  if (~reset_n || P==S_MAIN_INIT ||( P_next == S_MAIN_LEVEL1 && P!=S_MAIN_LEVEL1) ||( P_next == S_MAIN_LEVEL2 && P!=S_MAIN_LEVEL2)/*||P == S_MAIN_UPUP*/) begin
    touch_block <= 0;
    pre_touch_block <= 0;
  end
  else /*if (P==S_MAIN_LEVEL1)*/  begin
    case(direction)
      2'b00: begin //right
        if (pos_x[0]+32 == block_x[0] && pos_y[0] == block_y[0]) touch_block <= 1;
        else if (pos_x[0]+32 == block_x[1] && pos_y[0]==block_y[1])  touch_block <= 1;
        else if (pos_x[0]+32 == block_x[2] && pos_y[0]==block_y[2])  touch_block <= 1;
        else if (pos_x[0]+32 == block_x[3] && pos_y[0]==block_y[3])  touch_block <= 1;
        else if (pos_x[0]+32 == block_x[4] && pos_y[0]==block_y[4])  touch_block <= 1;
        else if (pos_x[0]+32 == block_x[5] && pos_y[0]==block_y[5])  touch_block <= 1;
        else if (pos_x[0]+32 == block_x[6] && pos_y[0]==block_y[6])  touch_block <= 1;
        else if (pos_x[0]+32 == block_x[7] && pos_y[0]==block_y[7])  touch_block <= 1;
        else if (pos_x[0]+32 == block_x[8] && pos_y[0]==block_y[8])  touch_block <= 1;
        else if (pos_x[0]+32 == block_x[9] && pos_y[0]==block_y[9])  touch_block <= 1;
        else begin
            touch_block <= 0;
            pre_touch_block <= 0;
        end
      end
      2'b01: begin  //left
        if (pos_x[0]-32 == block_x[0] && pos_y[0]==block_y[0])  touch_block <= 1;
        else if (pos_x[0]-32 == block_x[1] && pos_y[0]==block_y[1])  touch_block <= 1;
        else if (pos_x[0]-32 == block_x[2] && pos_y[0]==block_y[2])  touch_block <= 1;
        else if (pos_x[0]-32 == block_x[3] && pos_y[0]==block_y[3])  touch_block <= 1;
        else if (pos_x[0]-32 == block_x[4] && pos_y[0]==block_y[4])  touch_block <= 1;
        else if (pos_x[0]-32 == block_x[5] && pos_y[0]==block_y[5])  touch_block <= 1;
        else if (pos_x[0]-32 == block_x[6] && pos_y[0]==block_y[6])  touch_block <= 1;
        else if (pos_x[0]-32 == block_x[7] && pos_y[0]==block_y[7])  touch_block <= 1;
        else if (pos_x[0]-32 == block_x[8] && pos_y[0]==block_y[8])  touch_block <= 1;
        else if (pos_x[0]-32 == block_x[9] && pos_y[0]==block_y[9])  touch_block <= 1;
        else begin
            touch_block <= 0;
            pre_touch_block <= 0;
        end
      end
      2'b11: begin //d
        if (pos_y[0]+32 == block_y[0] && pos_x[0] == block_x[0])  touch_block <= 1;
        else if (pos_y[0]+32 == block_y[1] && pos_x[0] == block_x[1])  touch_block <= 1;
        else if (pos_y[0]+32 == block_y[2] && pos_x[0] == block_x[2])  touch_block <= 1;
        else if (pos_y[0]+32 == block_y[3] && pos_x[0] == block_x[3])  touch_block <= 1;
        else if (pos_y[0]+32 == block_y[4] && pos_x[0] == block_x[4])  touch_block <= 1;
        else if (pos_y[0]+32 == block_y[5] && pos_x[0] == block_x[5])  touch_block <= 1;
        else if (pos_y[0]+32 == block_y[6] && pos_x[0] == block_x[6])  touch_block <= 1;
        else if (pos_y[0]+32 == block_y[7] && pos_x[0] == block_x[7])  touch_block <= 1;
        else if (pos_y[0]+32 == block_y[8] && pos_x[0] == block_x[8])  touch_block <= 1;
        else if (pos_y[0]+32 == block_y[9] && pos_x[0] == block_x[9])  touch_block <= 1;
        else begin
            touch_block <= 0;
            pre_touch_block <= 0;
        end
      end
      2'b10: begin //up
        if (pos_y[0]-32 == block_y[0] && pos_x[0] == block_x[0])  touch_block <= 1;
        else if (pos_y[0]-32 == block_y[1] && pos_x[0] == block_x[1])  touch_block <= 1;
        else if (pos_y[0]-32 == block_y[2] && pos_x[0] == block_x[2])  touch_block <= 1;
        else if (pos_y[0]-32 == block_y[3] && pos_x[0] == block_x[3])  touch_block <= 1;
        else if (pos_y[0]-32 == block_y[4] && pos_x[0] == block_x[4])  touch_block <= 1;
        else if (pos_y[0]-32 == block_y[5] && pos_x[0] == block_x[5])  touch_block <= 1;
        else if (pos_y[0]-32 == block_y[6] && pos_x[0] == block_x[6])  touch_block <= 1;
        else if (pos_y[0]-32 == block_y[7] && pos_x[0] == block_x[7])  touch_block <= 1;
        else if (pos_y[0]-32 == block_y[8] && pos_x[0] == block_x[8])  touch_block <= 1;
        else if (pos_y[0]-32 == block_y[9] && pos_x[0] == block_x[9])  touch_block <= 1;
        else begin
            touch_block <= 0;
            pre_touch_block <= 0;
        end
      end
    endcase
  end
end

//set pre touch block
/*always@ (posedge clk) begin
  if (touch_block) begin
    if (pre_touch_block ==0)  begin
      pre_touch_block <= 1;
      score <= score - 1;
    end
  end
end*/

//point
always@ (posedge clk) begin
  if (~reset_n || P==S_MAIN_INIT ||( P_next == S_MAIN_LEVEL1 && P!=S_MAIN_LEVEL1)) begin
    point_enable <= 10'b0000011111; // @@
    snake_enable <= {5'b00000,5'b00000,5'b00000,5'b11111};
    block_enable <= {5'b00000,5'b00000,5'b00000,5'b11111,5'b11111};
    score <= 0;
    snake_length <= 5;
  end
  else if(level==1) begin
    point_enable <= 10'b0111111111; // @@
    snake_enable <= {5'b00000,5'b00000,5'b00000,5'b11111};
    block_enable <= {5'b11111,5'b11111,5'b11111,5'b11111,5'b11111};
    score <= 0;
    snake_length <= 5;
  end
  else if (P==S_MAIN_LEVEL1) begin
    if (pos_x[0] == point_x[0] && pos_y[0] == point_y[0] && point_enable[0]==1)  begin 
         point_enable[0]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
    else if (pos_x[1] == point_x[1] && pos_y[1] == point_y[1] && point_enable[1]==1)  begin 
         point_enable[1]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
    else if (pos_x[2] == point_x[2] && pos_y[2] == point_y[2] && point_enable[2]==1)  begin 
         point_enable[2]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
    else if (pos_x[3] == point_x[3] && pos_y[3] == point_y[3] && point_enable[3]==1)  begin 
         point_enable[3]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
    else if (pos_x[4] == point_x[4] && pos_y[4] == point_y[4] && point_enable[4]==1)  begin 
         point_enable[4]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
    else if (pos_x[5] == point_x[5] && pos_y[5] == point_y[5] && point_enable[5]==1)  begin 
         point_enable[5]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
    else if (pos_x[6] == point_x[6] && pos_y[6] == point_y[6] && point_enable[6]==1)  begin 
         point_enable[6]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
    else if (pos_x[7] == point_x[7] && pos_y[7] == point_y[7] && point_enable[7]==1)  begin 
         point_enable[7]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
    else if (pos_x[8] == point_x[8] && pos_y[8] == point_y[8] && point_enable[8]==1)  begin 
         point_enable[8]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
    else if (pos_x[9] == point_x[9] && pos_y[9] == point_y[9] && point_enable[9]==1)  begin 
         point_enable[9]<=0;
         score <= score + 1;
         snake_enable[snake_length] <= 1;
         snake_length = snake_length+1;
    end
  end
  
  
  if (touch_block) begin
    if (pre_touch_block ==0)  begin
      pre_touch_block <= 1;
      score <= score - 1;
    end
  end
end


//block
always @(posedge clk) begin
  if(~reset_n ||( P!=S_MAIN_LEVEL1 && P_next == S_MAIN_LEVEL1)) level<=0;
  else if(P_next==S_MAIN_LEVEL2 && P!=S_MAIN_LEVEL2) level <= 1;
  
  if(level==0)begin
  //block
    block_x[0] <= 5*BLOCK_SIZE-1;
    block_x[1] <= 6*BLOCK_SIZE-1;
    block_x[2] <= 7*BLOCK_SIZE-1;
    block_x[3] <= 11*BLOCK_SIZE-1;
    block_x[4] <= 12*BLOCK_SIZE-1;
    block_x[5] <= 12*BLOCK_SIZE-1;
    block_x[6] <= 16*BLOCK_SIZE-1;
    block_x[7] <= 17*BLOCK_SIZE-1;
    block_x[8] <= 17*BLOCK_SIZE-1;
    block_x[9] <= 17*BLOCK_SIZE-1;
    block_y[0] <= 11*BLOCK_SIZE-1;
    block_y[1] <= 5*BLOCK_SIZE-1;
    block_y[2] <= 4*BLOCK_SIZE-1;
    block_y[3] <= 8*BLOCK_SIZE-1;
    block_y[4] <= 8*BLOCK_SIZE-1;
    block_y[5] <= 9*BLOCK_SIZE-1;
    block_y[6] <= 14*BLOCK_SIZE-1;
    block_y[7] <= 3*BLOCK_SIZE-1;
    block_y[8] <= 4*BLOCK_SIZE-1;
    block_y[9] <= 14*BLOCK_SIZE-1;
    
    //point
    point_x[0] <= 4*BLOCK_SIZE-1;
    point_x[1] <= 7*BLOCK_SIZE-1;
    point_x[2] <= 11*BLOCK_SIZE-1;
    point_x[3] <= 16*BLOCK_SIZE-1;
    point_x[4] <= 18*BLOCK_SIZE-1;
    point_y[0] <= 11*BLOCK_SIZE-1;
    point_y[1] <= 3*BLOCK_SIZE-1;
    point_y[2] <= 9*BLOCK_SIZE-1;
    point_y[3] <= 4*BLOCK_SIZE-1;
    point_y[4] <= 12*BLOCK_SIZE-1;
  end
  else if(level==1) begin
    block_x[0] <= 3*BLOCK_SIZE-1;
    block_x[1] <= 4*BLOCK_SIZE-1;
    block_x[2] <= 4*BLOCK_SIZE-1;
    block_x[3] <= 4*BLOCK_SIZE-1;
    block_x[4] <= 5*BLOCK_SIZE-1; 
    block_x[5] <= 5*BLOCK_SIZE-1;
    block_x[6] <= 6*BLOCK_SIZE-1;
    block_x[7] <= 9*BLOCK_SIZE-1;
    block_x[8] <= 10*BLOCK_SIZE-1;
    block_x[9] <= 11*BLOCK_SIZE-1; 
    block_x[10] <= 11*BLOCK_SIZE-1;
    block_x[11] <= 11*BLOCK_SIZE-1;
    block_x[12] <= 11*BLOCK_SIZE-1;
    block_x[13] <= 12*BLOCK_SIZE-1;
    block_x[14] <= 13*BLOCK_SIZE-1;
    block_x[15] <= 15*BLOCK_SIZE-1;
    block_x[16] <= 15*BLOCK_SIZE-1;
    block_x[17] <= 16*BLOCK_SIZE-1;
    block_x[18] <= 16*BLOCK_SIZE-1;
    block_x[19] <= 17*BLOCK_SIZE-1;
    block_x[20] <= 17*BLOCK_SIZE-1;
    block_x[21] <= 17*BLOCK_SIZE-1;
    block_x[22] <= 18*BLOCK_SIZE-1;
    block_x[23] <= 18*BLOCK_SIZE-1;
    block_x[24] <= 19*BLOCK_SIZE-1;
    
    block_y[0] <= 11*BLOCK_SIZE-1;
    block_y[1] <= 6*BLOCK_SIZE-1;
    block_y[2] <= 10*BLOCK_SIZE-1;
    block_y[3] <= 12*BLOCK_SIZE-1;
    block_y[4] <= 5*BLOCK_SIZE-1;
    block_y[5] <= 6*BLOCK_SIZE-1;
    block_y[6] <= 5*BLOCK_SIZE-1;
    block_y[7] <= 8*BLOCK_SIZE-1;
    block_y[8] <= 12*BLOCK_SIZE-1;
    block_y[9] <= 10*BLOCK_SIZE-1;
    block_y[10] <= 11*BLOCK_SIZE-1;
    block_y[11] <= 12*BLOCK_SIZE-1;
    block_y[12] <= 13*BLOCK_SIZE-1;
    block_y[13] <= 12*BLOCK_SIZE-1;
    block_y[14] <= 12*BLOCK_SIZE-1;
    block_y[15] <= 8*BLOCK_SIZE-1;
    block_y[16] <= 9*BLOCK_SIZE-1;
    block_y[17] <= 4*BLOCK_SIZE-1;
    block_y[18] <= 8*BLOCK_SIZE-1;
    block_y[19] <= 3*BLOCK_SIZE-1;
    block_y[20] <= 4*BLOCK_SIZE-1;
    block_y[21] <= 7*BLOCK_SIZE-1;
    block_y[22] <= 3*BLOCK_SIZE-1;
    block_y[23] <= 14*BLOCK_SIZE-1;
    block_y[24] <= 13*BLOCK_SIZE-1;
    
    point_x[0] <= 4*BLOCK_SIZE-1;
    point_x[1] <= 5*BLOCK_SIZE-1;
    point_x[2] <= 10*BLOCK_SIZE-1;
    point_x[3] <= 10*BLOCK_SIZE-1;
    point_x[4] <= 10*BLOCK_SIZE-1;
    point_x[5] <= 12*BLOCK_SIZE-1;
    point_x[6] <= 12*BLOCK_SIZE-1;
    point_x[7] <= 15*BLOCK_SIZE-1;
    point_x[8] <= 18*BLOCK_SIZE-1;
    
    point_y[0] <= 5*BLOCK_SIZE-1;
    point_y[1] <= 11*BLOCK_SIZE-1;
    point_y[2] <= 9*BLOCK_SIZE-1;
    point_y[3] <= 11*BLOCK_SIZE-1;
    point_y[4] <= 13*BLOCK_SIZE-1;
    point_y[5] <= 11*BLOCK_SIZE-1;
    point_y[6] <= 13*BLOCK_SIZE-1;
    point_y[7] <= 7*BLOCK_SIZE-1;
    point_y[8] <= 4*BLOCK_SIZE-1;
  end
end

//block
genvar idx1, idx2, idx3;
generate
  for (idx1 = 0; idx1 < MAX_LEN; idx1 = idx1+1)  begin // ##
    assign snake_region[idx1] =
           (pixel_y < (pos_y[idx1]+1) && pixel_y >= (pos_y[idx1] -31) &&
           pixel_x < (pos_x[idx1]+1) && pixel_x >= (pos_x[idx1] -31)) && snake_enable[idx1];
           // "63": 32*2-1 (block length)
           // the region of snake's block 
  end
  for (idx2 = 0; idx2 < 25; idx2 = idx2+1)  begin
    assign block_region[idx2] =
           (pixel_y < (block_y[idx2]+1) && pixel_y >= (block_y[idx2] -31) &&
           pixel_x < (block_x[idx2]+1) && pixel_x >= (block_x[idx2] -31)) && block_enable[idx2];
  end
  for (idx3 = 0; idx3 < 10; idx3 = idx3+1)  begin
    assign point_region[idx3] =
           (pixel_y < (point_y[idx3]+1) && pixel_y >= (point_y[idx3] -31) &&
           pixel_x < (point_x[idx3]+1) && pixel_x >= (point_x[idx3] -31)) && point_enable[idx3];
  end
endgenerate
assign num_region = pixel_y < 64 && pixel_x <64;

always @ (posedge clk) begin
  if (~reset_n) begin
    pixel_addr_bg <= 0;
    pixel_addr_block <= 0;
    pixel_addr_point <= 0;
    pixel_addr_head <= 0;
    pixel_addr_body <= 0;
    pixel_addr_num0 <= 0;
    pixel_addr_num5 <= 0;
  end
  else begin
    // put the pixel of the background on the screen
    // Scale up a 320x240 image for the 640x480 display.
    // (pixel_x, pixel_y) ranges from (0,0) to (639, 479)
    pixel_addr_bg <= (pixel_y >> 1) * VBUF_W + (pixel_x >> 1);
    if (snake_region[0])// put the pixel of snake's head on the screen
        pixel_addr_head <= snake_h_b[direction] +((pixel_y)-pos_y[0]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[0]));// ##
    else pixel_addr_head <= snake_h_b[0];
    
    if (snake_region[1] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[1]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[1]));
    else if (snake_region[2] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[2]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[2]));
    else if (snake_region[3] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[3]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[3]));
    else if (snake_region[4] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[4]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[4]));
    else if (snake_region[5] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[5]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[5]));
    else if (snake_region[6] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[6]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[6]));
    else if (snake_region[7] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[7]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[7]));
    else if (snake_region[8] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[8]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[8]));
    else if (snake_region[9] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[9]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[9]));
    else if (snake_region[10] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[10]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[10]));
    else if (snake_region[11] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[11]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[11]));
    else if (snake_region[12] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[12]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[12]));
    else if (snake_region[13] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[13]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[13]));
    else if (snake_region[14] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[14]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[14]));
    else if (snake_region[15] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[15]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[15]));
    else if (snake_region[16] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[16]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[16]));
    else if (snake_region[17] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[17]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[17]));
    else if (snake_region[18] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[18]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[18]));
    else if (snake_region[19] != 0)// put the pixel of snake's body@@
        pixel_addr_body <= snake_h_b[4]+((pixel_y)-pos_y[19]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-pos_x[19]));
    else pixel_addr_body <= snake_h_b[4];
    
    if (block_region[0] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[0]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[0]));
    else if (block_region[1] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[1]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[1]));
    else if (block_region[2] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[2]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[2]));
    else if (block_region[3] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[3]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[3]));
    else if (block_region[4] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[4]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[4]));
    else if (block_region[5] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[5]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[5]));
    else if (block_region[6] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[6]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[6]));
    else if (block_region[7] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[7]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[7]));
    else if (block_region[8] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[8]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[8]));
    else if (block_region[9] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[9]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[9]));
    else if (block_region[10] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[10]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[10]));
    else if (block_region[11] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[11]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[11]));
    else if (block_region[12] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[12]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[12]));
    else if (block_region[13] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[13]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[13]));
    else if (block_region[14] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[14]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[14]));
    else if (block_region[15] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[15]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[15]));
    else if (block_region[16] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[16]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[16]));
    else if (block_region[17] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[17]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[17]));
    else if (block_region[18] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[18]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[18]));
    else if (block_region[19] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[19]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[19]));
    else if (block_region[20] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[20]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[20]));
    else if (block_region[21] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[21]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[21]));
    else if (block_region[22] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[22]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[22]));
    else if (block_region[23] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[23]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[23]));
    else if (block_region[24] != 0)
        pixel_addr_block <= block_addr +((pixel_y)-block_y[24]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-block_x[24]));    
    else pixel_addr_block <= block_addr;
    if (point_region[0] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[0]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[0]));
    else if (point_region[1] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[1]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[1]));
    else if (point_region[2] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[2]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[2]));
    else if (point_region[3] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[3]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[3]));
    else if (point_region[4] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[4]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[4]));
    else if (point_region[5] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[5]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[5]));
    else if (point_region[6] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[6]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[6]));
    else if (point_region[7] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[7]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[7]));
    else if (point_region[8] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[8]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[8]));
    else if (point_region[9] != 0)
        pixel_addr_point <= point_addr+((pixel_y)-point_y[9]+BLOCK_SIZE-1)*BLOCK_SIZE +((pixel_x +(BLOCK_SIZE-1)-point_x[9]));
    else pixel_addr_point <= point_addr;
    end
    if (num_region) begin
        if(score<5 && score>=0) begin
            pixel_addr_num0 <= num_addr[score]+((pixel_y)-63+BLOCK_SIZE*2-1)*BLOCK_SIZE*2 +((pixel_x +(BLOCK_SIZE*2-1)-63));
        end
        else begin
            pixel_addr_num5 <= num_addr[score]+((pixel_y)-63+BLOCK_SIZE*2-1)*BLOCK_SIZE*2 +((pixel_x +(BLOCK_SIZE*2-1)-63));
        end
    end
    
end

endmodule

