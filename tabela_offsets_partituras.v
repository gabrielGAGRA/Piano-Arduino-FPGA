// Descricao: Tabela combinacional de offsets de partituras para a Mega-ROM.
// Funcionamento: Mapeia o indice da musica (0..41) no endereco base dentro da Mega-ROM.

`timescale 1ns / 1ps
`default_nettype none

module tabela_offsets_partituras #(
  parameter AddrWidth = 14
)(
  input  wire [5:0]           musica_id,
  output reg  [AddrWidth-1:0] base_addr
);

  always @* begin
    base_addr = {AddrWidth{1'b0}};
    case (musica_id)
      6'd0: base_addr = 14'd0; // Axel_F
      6'd1: base_addr = 14'd0; // Bad_Romance
      6'd2: base_addr = 14'd0; // Beat_It
      6'd3: base_addr = 14'd0; // Careless_Whisper
      6'd4: base_addr = 14'd1; // Clair_de_Lune
      6'd5: base_addr = 14'd0; // Clocks
      6'd6: base_addr = 14'd799; // Do_Re_Mi_Fa
      6'd7: base_addr = 14'd0; // Epitafio
      6'd8: base_addr = 14'd0; // Fukashigi_No_Carte
      6'd9: base_addr = 14'd0; // Fur_Elise
      6'd10: base_addr = 14'd0; // Golden
      6'd11: base_addr = 14'd0; // Golden_Wind
      6'd12: base_addr = 14'd0; // Harry_Potter
      6'd13: base_addr = 14'd0; // Head_Over_Heels
      6'd14: base_addr = 14'd0; // Hey_Jude
      6'd15: base_addr = 14'd0; // Homem_Aranha_1900
      6'd16: base_addr = 14'd0; // Imperial_March
      6'd17: base_addr = 14'd0; // Interestelar
      6'd18: base_addr = 14'd807; // Jump_Up_Super_Star
      6'd19: base_addr = 14'd0; // Korobeiniki
      6'd20: base_addr = 14'd0; // Lugar_Ao_Sol
      6'd21: base_addr = 14'd0; // Magnetic
      6'd22: base_addr = 14'd0; // Mario
      6'd23: base_addr = 14'd0; // Minecraft_Sweden
      6'd24: base_addr = 14'd0; // Moonlight_Sonata_3mvt
      6'd25: base_addr = 14'd0; // Morning_Flower
      6'd26: base_addr = 14'd0; // Never_Gonna_Give_You_Up
      6'd27: base_addr = 14'd1624; // New_Donk_City
      6'd28: base_addr = 14'd0; // Numb
      6'd29: base_addr = 14'd0; // Pink_Panther
      6'd30: base_addr = 14'd0; // Radio_Ga_Ga
      6'd31: base_addr = 14'd0; // Sadness_And_Sorrow
      6'd32: base_addr = 14'd0; // Super_Idol
      6'd33: base_addr = 14'd0; // Susanne
      6'd34: base_addr = 14'd0; // Sweet_Child_O_Mine
      6'd35: base_addr = 14'd0; // Take_On_Me
      6'd36: base_addr = 14'd0; // Trem_Das_Onze
      6'd37: base_addr = 14'd0; // Undertale_Megalovania
      6'd38: base_addr = 14'd0; // We_Are_Number_One
      6'd39: base_addr = 14'd0; // When_Love_Takes_Over
      6'd40: base_addr = 14'd2094; // Wii_Sports
      6'd41: base_addr = 14'd0; // Zelda_Lost_Woods
      default: base_addr = {AddrWidth{1'b0}};
    endcase
  end

endmodule

`default_nettype wire
