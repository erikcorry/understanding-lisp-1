# Understanding LISP-1

LISP-1 was written by L. Peter Deutsch and Edmund C. Berkeley, completed when Peter was 17.

It ran on a PDP-1 18 bit minicomputer, and the report on it is
[here](http://s3data.computerhistory.org/pdp-1/DEC.pdp_1.1964.102650371.pdf).
It includes the macro-assembler source that I quote from here.

The PDP-1 instruction set is very strange by modern standards.  A summary is
[here](https://www.masswerk.at/spacewar/inside/pdp1-instructions.html).  Although
there is support for subroutines there is no stack, so it's hard to recurse.
The obvious calling convention has only one return address per function.

There's just one real working register, the accumulator.  In addition there
are various status registers, and of course the program counter, PC.

## jsp

The `jsp` instruction is the basic building block for subroutine calls.
It jumps to a new address and saves the program counter (return address) in the
accumulator.

Using this you can make a simple subroutine.  The assembler only allows
three-letter labels so the subroutine is called `mys` rather than
`my_subroutine`

```
mys,    dac end   /// Entry code.
                  /// Subroutine code here
end,    jmp .     /// Return instruction.
```

`jmp .` just means jump to the current address.  The dot is a common macro-assembler
pseudo-label that just indicates the current address it is assembling to.  But how
does jumping to the current address equal a return instruction?

What happens here is that the `dac` instruction (deposit-address-part) takes the
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

## jda

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

## cal

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

The purpose of this is to make a call into some part of the interpreter in such
a way that it stores the return address on the interpreter's software stack.
Thus it is set up so that when the interpreter unwinds its software stack it
will return right back to the machine code that called it.

It works by inspecting the instruction that called it to find the real
destination!

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
argument to the interpreter routine it is calling.  Then it uses the self-modified
jump to tail-call into the interpreter (confusing comment here - "make that the
return address from the interpreter").

## More to come.

If I decide to spend more time understanding this.
