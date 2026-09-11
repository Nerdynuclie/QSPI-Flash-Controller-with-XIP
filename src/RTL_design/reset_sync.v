//======================================================================
// reset_sync.v
//
// Async-assert / sync-deassert reset synchronizer.
//
// Purpose:
//   Takes an asynchronous, active-low reset (PRESETn) that may originate
//   from anywhere (POR, external pin, another clock domain, etc.) and
//   produces a locally clean, active-low reset for ONE clock domain.
//
//   - Assertion of async_rst_n propagates to sync_rst_n immediately
//     (asynchronously), so the domain resets right away with no
//     dependency on clk toggling.
//   - De-assertion of async_rst_n is re-synchronized to two consecutive
//     rising edges of clk before sync_rst_n releases, so there is no
//     risk of a reset-removal timing violation on any flop that uses
//     sync_rst_n as its own async reset.
//
// Usage:
//   One instance per clock domain. Do NOT share a single instance's
//   output across two different clocks.
//
//   reset_sync u_reset_sync_spi
//   (
//       .clk          (spi_clk),
//       .async_rst_n  (PRESETn),
//       .sync_rst_n   (spi_rst_n)
//   );
//
// Note:
//   A synchronizer cell's OWN reset (e.g. two_ff_sync) should typically
//   stay tied to the raw async_rst_n of its source domain rather than a
//   downstream sync_rst_n, to avoid racing the signal it is meant to
//   capture. See project notes.
//======================================================================

module reset_sync
(
    input  wire clk,          // destination domain clock
    input  wire async_rst_n,  // asynchronous active-low reset (source)
    output wire sync_rst_n    // synchronized active-low reset (destination domain)
);

reg rst_ff1;
reg rst_ff2;

// Async assert (either flop clears immediately when async_rst_n drops),
// sync deassert (release ripples through two clk edges before flop2 goes high).
always @(posedge clk or negedge async_rst_n)
begin
    if(!async_rst_n)
    begin
        rst_ff1 <= 1'b0;
        rst_ff2 <= 1'b0;
    end
    else
    begin
        rst_ff1 <= 1'b1;
        rst_ff2 <= rst_ff1;
    end
end

assign sync_rst_n = rst_ff2;

endmodule