library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CacheController is
    Port (
        clk : in STD_LOGIC;
        ADDR : out STD_LOGIC_VECTOR(15 downto 0);
        DOUT : out STD_LOGIC_VECTOR(7 downto 0);
        sAddra : out STD_LOGIC_VECTOR(7 downto 0);
        sDina : out STD_LOGIC_VECTOR(7 downto 0);
        sDouta : out STD_LOGIC_VECTOR(7 downto 0);
        sD_Addra : out STD_LOGIC_VECTOR(15 downto 0);
        sD_Dina : out STD_LOGIC_VECTOR(7 downto 0);
        sD_Douta : out STD_LOGIC_VECTOR(7 downto 0);
        cacheAddr : out STD_LOGIC_VECTOR(7 downto 0);
        WR_RD, MEMSTRB, RDY ,CS : out STD_LOGIC
    );
end CacheController;

architecture Behavioral of CacheController is
-- CPU Signals
signal CPU_Dout, CPU_Din : STD_LOGIC_VECTOR(7 downto 0);
signal CPU_ADD : STD_LOGIC_VECTOR (15 downto 0);
signal CPU_W_R,CPU_CS,CPU_RDY : STD_LOGIC;
signal cpu_tag : STD_LOGIC_VECTOR(7 downto 0);
signal index : STD_LOGIC_VECTOR(2 downto 0);
signal offset : STD_LOGIC_VECTOR(4 downto 0);

-- SRAM Signals
signal Dbit : STD_LOGIC_VECTOR(7 downto 0):= (others=>'0');
signal Vbit : STD_LOGIC_VECTOR(7 downto 0):= (others=>'0');
signal sADD, sDin, sDout : STD_LOGIC_VECTOR(7 downto 0);
signal sWen : STD_LOGIC_VECTOR(0 DOWNTO 0);
signal TAGWen : STD_LOGIC := '0';

-- SDRAM Signals
signal SDRAM_Din,SDRAM_Dout : STD_LOGIC_VECTOR(7 downto 0);
signal SDRAM_ADD : STD_LOGIC_VECTOR(15 downto 0);
signal SDRAM_MSTRB,SDRAM_W_R : STD_LOGIC;
signal counter : integer := 0;
signal sdoffset : integer := 0;

-- SRAM array
type cachememory is array (7 downto 0) of STD_LOGIC_VECTOR(7 downto 0);
signal memtag: cachememory := (others=>(others=>'0'));

-- State machine
TYPE state_value IS (state0, state1, state2, state3, state4);
signal state_current : state_value := state3;
signal state : STD_LOGIC_VECTOR(3 downto 0);

begin


process(clk)
begin
    if rising_edge(clk) then

--state 3: idle

        if (state_current = state3) then
            CPU_RDY <= '1';
            if (CPU_CS = '1') then
                state_current <= state4; 
                state <= "0100";
            end if;

  --state 4: ready

        elsif (state_current = state4) then
            CPU_RDY <= '0';
            cpu_tag <= CPU_ADD(15 downto 8);
            index <= CPU_ADD(7 downto 5);
            offset <= CPU_ADD(4 downto 0);
            SDRAM_ADD(15 downto 5) <= CPU_ADD(15 downto 5);
            sADD(7 downto 0) <= CPU_ADD(7 downto 0);
            sWen <= "0";

           
            if (Vbit(to_integer(unsigned(index)))='1' and
                memtag(to_integer(unsigned(index)))=cpu_tag) then
                TAGWen <= '1';
                state_current <= state0;   -- cache hit
                state <= "0000";
            else
                TAGWen <= '0';
                if (Dbit(to_integer(unsigned(index)))='1' and
                    Vbit(to_integer(unsigned(index)))='1') then
                    state_current <= state2; -- write-back
                    state <= "0010";
                else
                    state_current <= state1; -- load new block
                    state <= "0001";
                end if;
            end if;

--state 0: R/W Execution

        elsif (state_current = state0) then
            if (CPU_W_R = '1') then
                sWen <= "1";
                Dbit(to_integer(unsigned(index))) <= '1';
                Vbit(to_integer(unsigned(index))) <= '1';
                sDin <= CPU_Dout;
            else
                CPU_Din <= sDout;
            end if;

            state_current <= state3;  -- back to idle
            state <= "0011";

       --state 1: miss and Dbit=0
        elsif (state_current = state1) then
            if (counter = 64) then
                counter <= 0;
                Vbit(to_integer(unsigned(index))) <= '1';
                memtag(to_integer(unsigned(index))) <= cpu_tag;
                sdoffset <= 0;
                state_current <= state0;
                state <= "0000";
            else
                if (counter mod 2 = 1) then
                    SDRAM_MSTRB <= '0';
                else
                    SDRAM_ADD(4 downto 0) <= std_logic_vector(to_unsigned(sdoffset,5));
                    SDRAM_W_R <= '0';
                    SDRAM_MSTRB <= '1';
                    sADD(7 downto 5) <= index;
                    sADD(4 downto 0) <= std_logic_vector(to_unsigned(sdoffset,5));
                    sDin <= SDRAM_Dout;
                    sWen <= "1";
                    sdoffset <= sdoffset + 1;
                end if;
                counter <= counter + 1;
            end if;


     --state 2: miss and Dbit=1

        elsif (state_current = state2) then
            if (counter = 64) then
                counter <= 0;
                Dbit(to_integer(unsigned(index))) <= '0';
                sdoffset <= 0;
                state_current <= state1;
                state <= "0001";
            else
                if (counter mod 2 = 1) then
                    SDRAM_MSTRB <= '0';
                else
                    SDRAM_ADD(4 downto 0) <= std_logic_vector(to_unsigned(sdoffset,5));
                    SDRAM_W_R <= '1';
                    sADD(7 downto 5) <= index;
                    sADD(4 downto 0) <= std_logic_vector(to_unsigned(sdoffset,5));
                    sWen <= "0";
                    SDRAM_Din <= sDout;
                    SDRAM_MSTRB <= '1';
                    sdoffset <= sdoffset + 1;
                end if;
                counter <= counter + 1;
            end if;
        end if;
    end if;
end process;


MEMSTRB <= SDRAM_MSTRB;
ADDR <= CPU_ADD;
WR_RD <= CPU_W_R;
DOUT <= CPU_Din;
RDY <= CPU_RDY;
CS <= CPU_CS;

sAddra <= sADD;
sDina <= sDin;
sDouta <= sDout;
sD_Addra <= SDRAM_ADD;
sD_Dina <= SDRAM_Din;
sD_Douta <= SDRAM_Dout;
cacheAddr <= CPU_ADD(15 downto 8);

end Behavioral;
