package qengine

import spinal.core._
import spinal.lib._

// Hardware definition
// How many dma out?
// How many slices in?
// Width of data?
// What is the latency of the parent module such that we need to store order for this long
case class VmemDatArbOut1_1(DMA: Int = 4, SLICE: Int = 16, W: Int = 32, UPLATENCY: Int = 32) extends Component {
  // dump params
  println(s"DMA = $DMA")
  println(s"SLICE = $SLICE")
  println(s"UPLATENCY = $UPLATENCY")

  // Validate parameters
  require(DMA > 0, "DMA must be positive")
  require(SLICE > 0, "SLICE must be positive")
  require(W > 0, "W must be positive")
  require(UPLATENCY > 0, "UPLATENCY must be positive")

  // Calculate bits needed once
  val SLICEB = log2Up(SLICE) // 4
  val DMAB = log2Up(DMA) // 2

  println(s"SLICEB = $SLICEB")
  println(s"DMAB = $DMAB")

  val io = new Bundle {
    // Input interfaces (16)
    // val in_data = in(Bits(32 bits)).setAsComb.setAsArray(16) // 32-bit data from each input, as array

    // could be UInt(W bits)
    // but this module doesn't touch the data in any way so:
    // It better represents the semantic meaning of "just passing data through"
    // We also have 2 (DMAB) more bits which are the two address bits
    // This tells us which DMA this read came from. we correlate this with dma_order
    // to route correctly
    val in_data = Vec(slave Stream(Bits(DMAB bits) ## Bits(W bits)), SLICE)

    // I think this is correct
    // one per DMA.
    // each one needs to represent an index to a SLICE
    val dma_order = Vec(slave Stream(UInt(SLICEB bits)), DMA)

    val out_data = Vec(master Stream(Bits(W bits)), DMA)
  }

  // Extension methods to access the components of the stream
  // this is useful because I glued dma and data together to work with Stream()
  // and when we want to access each part, we need these confusing indices in the code
  // so I put them here and named them. "Pimper" enhances an existing class without modifying it's code
  implicit class DataStreamPimper(stream: Stream[Bits]) {
    def dma: UInt = stream.payload(W+DMAB-1 downto W).asUInt
    def data: Bits = stream.payload(W-1 downto 0)
  }

  // each time the parent writes to a slice. we get a write signifying
  // "For dma D the next slice should be S"
  val orderFifos = for (i <- 0 until DMA) yield {
    StreamFifo(
      dataType = UInt(SLICEB bits),
      depth    = UPLATENCY,
      latency  = 1
    ).setDefinitionName("ArbStreamFifo1")
    // setDefinitionName is required because this will conflict with VexRiscv's Fifos otherwise
  }

  io.dma_order.zipWithIndex.foreach{ case (an_order, i) =>
    orderFifos(i).io.push << an_order
  }

  // Initialize all slice ready signals to False
  // for (slice <- 0 until SLICE) {
  //   io.in_data(slice).ready := False
  // }

  // Duplicate each input port, but dedicated for an output dma
  // DMA index is multiplied by 16
  // DMA 0 SLICE [0-15] [0-15]
  // DMA 1 SLICE [0-15] [16-31]
  val fanout = Vec(for (i <- 0 until DMA*SLICE) yield {
    // I think this could be replaced by an EB 1.5 if that's more simple
    StreamFifo(
      dataType = Bits(W bits),
      depth    = 2,
      latency  = 1 // should be 1 probably
    ).setDefinitionName("ArbStreamFifo2").io
    // important to put .io at the end here
    // this means fanout is a Vec(chisel types)
    // as opposed to a sequence of scala types
    // this is required if we want hardware to be able to index into fanout
    // if needed this can be renamed ot fanoutObjects, and then this added:
    // val fanout = Vec(fanoutObjects.map(_.io))
  })


  // Initialize all fanout push valid signals to False
  fanout.foreach(_.push.valid := False)
  // Also initialize all fanout push payloads to prevent latches
  fanout.foreach(_.push.payload := B(0, W bits))
  fanout.foreach(_.pop.ready := False)

  def getFanoutIndex(dma: UInt, slice: UInt): UInt = {
    require(dma.getWidth == DMAB, f"dma must be ${DMAB} bits, not ${dma.getWidth}")
    require(slice.getWidth == SLICEB, f"slice must be ${SLICEB} bits, not ${slice.getWidth}")
    val res = (dma ## slice).asUInt
    require(res.getWidth == (SLICEB+DMAB), f"getFanoutIndex return value must be ${(SLICEB+DMAB)} bits, not ${res.getWidth}")
    res
  }
  // def getFanoutIndex(dma: Int, slice: Int): Int = {
  //   dma * SLICE + slice
  // }

  // Deal with the fanout, one for each of the 16 inputs, fan out to our 64 holding array
  for (s <- 0 until SLICE) {
    // sugar to shorten this
    val readfrom = io.in_data(s)

    val idx: UInt = getFanoutIndex(readfrom.dma, U(s, SLICEB bits))

    // sugar to shorten this
    val fan = fanout(idx)

    fan.push.payload := readfrom.data

    // when slice input is valid, and the fan is ready
    // send the transaction
    // previously this was
    // when(readfrom.valid && fan.push.ready) {
    //     readfrom.ready := True
    //     fan.push.valid := True
    // }
    readfrom.ready := fan.push.ready
    fan.push.valid := readfrom.valid

  }

  // for each dma, consider the input order, as well as the 16 fifos that are relevant
  for (dma <- 0 until DMA) {
    // does this matter if inside or outside?
    val expectedSlice: UInt = orderFifos(dma).io.pop.payload
    require(expectedSlice.getWidth == SLICEB)

    val fanoutIndex = getFanoutIndex(U(dma, DMAB bits), expectedSlice)

    io.out_data(dma).payload := fanout(fanoutIndex).pop.payload

    val responseValid = orderFifos(dma).io.pop.valid && fanout(fanoutIndex).pop.valid
    io.out_data(dma).valid := responseValid
    orderFifos(dma).io.pop.ready := io.out_data(dma).ready && fanout(fanoutIndex).pop.valid
    fanout(fanoutIndex).pop.ready := io.out_data(dma).ready && orderFifos(dma).io.pop.valid

    // was previously
    // when(orderFifos(dma).io.pop.valid && fanout(fanoutIndex).pop.valid) {
    //   orderFifos(dma).io.pop.ready := True
    //   io.out_data(dma).valid := True
    //   fanout(fanoutIndex).pop.ready := True
    // }
  }

  // just drive everything to zero until I figure it out
  // for (dma <- 0 until DMA) {
  //   io.out_data(dma).valid := False
  //   io.out_data(dma).payload := B(0, W bits)
  //   orderFifos(dma).io.pop.ready := False
  // }

}

object VmemDatArbOut1_1Verilog extends App {
  Config.spinal.generateVerilog(VmemDatArbOut1_1())
}

object VmemDatArbOut1_1Vhdl extends App {
  Config.spinal.generateVhdl(VmemDatArbOut1_1())
}


// Capital False and True are HDL types
// lower case false and true are spinal type
