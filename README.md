# Understanding LISP-1

LISP-1 was written by L. Peter Deutsch and Edmund C. Berkeley, completed when Peter was 17.
It is possibly the first REPL we know of.

It ran on a PDP-1 18 bit minicomputer, and the report on it is
[here](http://s3data.computerhistory.org/pdp-1/DEC.pdp_1.1964.102650371.pdf).
It includes the macro-assembler source that I quote from here.

The PDP-1 instruction set is very strange by modern standards.  A summary is
[here](https://www.masswerk.at/spacewar/inside/pdp1-instructions.html).  Although
there is support for subroutines there is no stack, so it's hard to recurse.
The obvious calling convention has only one return address per function.

There are just two real working registers, the accumulator and the IO register.
In addition there are various status registers, and of course the program counter, PC.

## jsp instruction

The `jsp` instruction is the basic building block for subroutine calls.
It jumps to a new address and saves the program counter (return address) in the
accumulator.

Using this you can make a simple subroutine.  The assembler only allows
three-letter labels so the subroutine is called `mys` rather than
`my_subroutine`

```
mys,    dap end   /// Entry code.
                  /// Subroutine code here
end,    jmp .     /// Return instruction.
```

`jmp .` just means jump to the current address.  The dot is a common macro-assembler
pseudo-label that just indicates the current address it is assembling to.  But how
does jumping to the current address equal a return instruction?

What happens here is that the `dap` instruction (deposit-address-part) takes the
return address (placed in the accumulator by the `jsp` instruction and puts it
in the low bits (the address part) of the return instruction.  So it uses
self-modifying code as a normal way to return from a subroutine.

The instruction format of the PDP-1 has the opcode in the high bits and the low
bits are the argument, so this rewrites the `jmp` instruction to return to the
correct place.

As you can see this scheme does not allow for recursion.  The return address for
the previous invocation would get overwritten when you reenter the function.
Since it uses self-modifying code it also clearly would not work for ROM, but
the PDP-1 had no ROM, so that was not an issue.

## jda instruction

The `jsp` instruction is very useful for a subroutine call, but a little
inconvenient - given that there is only one register and it gets overwritten.
How to pass arguments?

This is where the `jda` instruction comes in.  It writes the accumulator to
an address, and then jumps to the following address.  Thus the subroutine/function
finds its argument just before the first instruction.  Consider `myf` (my\_function)

```
myf,    0        // Argument is written here.
        dap enf  // Write return address at the end.
        lac myf  // Load argument from the word before the function.
                 // Function goes here.
enf,    jmp .    // Return address overwritten here.
```

## cal instruction/stub

The `cal` instruction adds another layer of complexity.  Bizarrely, it ignores its
argument and always does a subroutine call (`jda`) to address 100.  (All
numbers are in octal - this is the 1960s after all.).

On its face this isn't very useful unless you have a subroutine at address 100 and
you want to call it with a different instruction for some reason.  But if we look at
the LISP-1 runtime it has a rather special stub at that address.  (The comments
are clearly written by a teenager!)

```
/// This is where cal goes!
/// This is the eval interpreter, duh-head!
/// so... where >is< rx?  A fair question, methinks.
	0
/// save return address
	dap rx
/// get address of original cal instruction
	sub (1
/// put it into next instruction
	dap .+1
/// get what was at that address
	lac xy
/// make that the return adddress from the interpreter
	dap ave+1
/// get return address back and push on stack
	lac rx
	jda pwl
/// advance, end
/// restore AC
ave,	lac 100
	exit
```

The purpose of this is to make a call, but using a stack of return addresses
like we are used to from modern systems.  The comments are very
interpreter-oriented, but really the only part that is interpreter-specific is
that it pushes the return address onto the interpreter stack.

Since the `cal` instruction ignores its argment this stub works by inspecting
the instruction that called it to find the real destination!

The assembly starts with a simple `0`.  Again, this is a word before the real
code for storing the accumulator/argument.

It temporarily stores the return address in a fixed position, `rx`.

Then it loads the actual destination, using the return address to locate
it.  For this it uses self-modifying code again, writing the next instruction
(`.+1`).  It writes the actual destination to the last instruction of the
stub, ready for a tail call.
(It does this by modifying a macro-assembler pseudo-instruction called `exit`
which presumably is equivalent to `jmp .`.)

Then it does a `jda` subroutine call to `pwl` which is a push subroutine that
pushes the return address onto the interpreter's stack.

After the push, it restores the accumulator from address 100, which was the
argument to whatever routine it is calling.  Then it uses the self-modified
jump to tail-call to the destination - often a part of the interpreter
(confusing comment here - "make that the return address from the interpreter").

A fun detail about this calling convention is after the tail call the argument
is both in the accumulator, but also in location 100.  Some functions use
the location 100 value instead of the accumulator.  This is especially convenient
because there is no instruction that uses the accumulator as a load address.

## uw routine

The "unsave word" routine would be called `pop` today, and the "push down list"
would be called the stack.

```
/retrieve word from pdl
	/unsave word; retrieve word from push down list
	/unsave word from list
uw,	0
uwl,	dap uwx
	lio i pdl
/// subtract 1 from pdl
	undex pdl
/// unsave word, exit
uwx,	exit
```

This is designed to be called directly with `jda`.  The old accumulator is placed
in the `uw` location, the accumulator contains the return address, and execution
starts at the next word, marked `uwl`.

The return address is used to overwrite the jmp instruction at `uwx` so we can return.

The top of stack is loaded into the IO register (which is where the caller
expects to find it).  The stack pointer (pdl) is then decremented, and we use the
previously modified jump instruction to return.

If the caller wants to restore the accumulator they can find it at the `uw` location.

The io register is clobbered by the return value.

## pwl routine

The push word on list function checks for stack overflow, jumping to qg2 if
the stack (push-down list) is too full.  It is otherwise quite straightforward
if you already understood the `uw` routine above:

```
/// push word on list (append word to push-down list)
/append word to pdl
pwl,	0
/// put return address into jmp instruction
	dap pwx
/// next position on push-down list
	idx pdl
	sad bfw
/// ran into bfw
	jmp qg2
/// restore accumulator
	lac pwl
/// put it onto list
	dac i pdl
/// push word exit
pwx,	exit
```

The accumulator is not clobbered.

## x stub

Functions return by jumping to the x stub.  It pops the return address
off the stack (push down list) by calling `uw`.  It clobbers the IO register,
but preserves the accumulator by reloading it from the header of the `uw`
function where it knows it was spilled.

```
/// exit from machine language LISP functions
x,	jda uw
	dio rx
	lac uw
/// return to calling sequence of a subroutine
rx,	exit
```

}

## vag routine

This is a routine for unpacking a tagged integer from a memory cell.
The numeric cell stores an 18 bit number in two consecutive words.
The first word has a numeric tag of 3 (binary 11) in the top two bits
and the low 16 bits of the numeric payload in the other 16 bits.

The second word provides the high bit and the sign bit in the lowest
bits.  The other 16 bits are unused as far as I can tell.

```
11 nnnn nnnn nnnn nnnn      .. .... .... ..... ...sn
```

As can be seen the numeric cell has the same size (two words) as a
cons cell.

The `vag` routine makes use of the fact that its argument has been
spilled by the entry code, so that it can be found at address 100.
Comments are mine:

```
/get numeric value
vag,	lio i 100    /// Indirect load of argument cell into IO register.
	cla          /// Clear accumulator.
	rcl 2s       /// Roll AC and IO left two places so AC has top two bits of IO.
	sas (3       /// Skip next instruction if AC == 3.
	jmp qi3      /// Jump to error if tag != 3 (numeric tag).
	idx 100      /// Increment argument to get word two of the cell.
	lac i 100    /// Indirect load of arg[1] into accumulator.
	rcl 8s       /// Roll AC and IO left 8 places.
	rcl 8s       /// Another 8 places.  AC now has the full 18 bit integer in it.
	jmp x        /// Return untagged result in AC.
```

## crn routine

Create number is a routine that takes an integer in the accumulator
and writes it to a newly allocated integer cell, returning the address
of the new cell in the accumulator.

Comments mine:

```
/create number
crn,	lio (jmp    // Load 600000 into IO.
	rcl 2s      // Rotate AC and IO together left 2.
	rar 2s      // Rotate AC right 2.
	dac 100     // Store the low 16 bits of AC in the argument location.
	jmp cpf     // Tail call to cons pair in full space.
```

The effect of this is to move the top two bits of AC to the low bits of
IO, and replace the top two bits of AC with a tag of 11, storing the
tagged value in 100, the argument location.  This means that writing
100 and IO to a cons cell will store a correctly tagged number in that cell.

Note that the `(jmp` instruction just happens to have the correct binary
pattern for this operation: `11_0000_0000_0000_0000`.  The author doesn't
think this worth a comment!

## cpf routine

Cons pair in full space.

```
cpf,	dzm ffi
	jmp cnc
```

Stores 0 in ffi, then tail calls to cnc (cons continuation routine).

I haven't worked out what ffi is for yet, but it's read by the GC.

## cns routine

Cons routine.

```
cns,	idx ffi
```

Increments ffi, then falls through to cnc

I haven't worked out what ffi is for yet, but it's read by the GC.

## cnc routine

Cons continuation.

This routine checks for free list exhaustion, and calls the garbage collector
if we are out of space.  Being out of space is indicating by the next free cons
cell being the nil object.

Comments mine:

```
cnc,	lac fre  /// Load the free list pointer.
	sad n    /// Compare with n, the location of nil.
	jmp gcs  /// Conditionally jump to the GC.
```

If there is no GC, it falls through to cna (cons, sub a).  If there is a GC the
GC jumps to cna when it is done.

## cna routine

Cons, sub a.

This routine allocates and populates a memory cell.
It assumes the free list has already been checked for
exhaustion.

On entry, AC points at the free cell, the desired car is in 100, the subroutine
argument location, and the the desired cdr is in the IO register.  On exit the
location of the new cell is in AC.

Comments mine:

```
cna,	dac t0     /// Spill AC (the new cell) to temp 0.
	lac 100    /// Load AC from 100, the subroutine arg location.
	dac i fre  /// Store AC through free pointer.
	idx fre    /// Increment free pointer to part two of cell.
	lac i fre  /// Load next cell in free list from part two of cell.
	dio i fre  /// Store IO in part two of cell.
	dac fre    /// Store new free cell in free list pointer.
	lac t0     /// Restore AC (the new cell) from temp 0.
	jmp x      /// Return from subroutine.
```

## xeq function

The xeq function is a LISP function for running a single machine code instruction.
That one instruction can be a jmp instruction though, so it can actually be
used to run any number of instructions.  The paper suggests 60nnnn to jump to
code at the 12 bit address nnnn.
