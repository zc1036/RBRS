
	.intel_syntax noprefix

	# Declare constants used for creating a multiboot header.
	.set ALIGN,    1<<0             # align loaded modules on page boundaries
	.set MEMINFO,  1<<1             # provide memory map
	.set FLAGS,    ALIGN | MEMINFO  # this is the Multiboot 'flag' field
	.set MAGIC,    0x1BADB002       # 'magic number' lets bootloader find the header
	.set CHECKSUM, -(MAGIC + FLAGS) # checksum of above, to prove we are multiboot
	.set VGA_WIDTH, 80
	.set VGA_HEIGHT, 25
    .set TERMINAL_BUFFER, 0xB8000

	# Declare a header as in the Multiboot Standard. We put this into a special
	# section so we can force the header to be in the start of the final program.
	# You don't need to understand all these details as it is just magic values that
	# is documented in the multiboot standard. The bootloader will search for this
	# magic sequence and recognize us as a multiboot kernel.
	.section .multiboot
	.align 4
	.long MAGIC
	.long FLAGS
	.long CHECKSUM

	# Currently the stack pointer register (esp) points at anything and using it may
	# cause massive harm. Instead, we'll provide our own stack. We will allocate
	# room for a small temporary stack by creating a symbol at the bottom of it,
	# then allocating 16384 bytes for it, and finally creating a symbol at the top.
	.section .bootstrap_stack, "aw", @nobits
stack_bottom:
	.skip 16384 # 16 KiB
stack_top:

	# The linker script specifies _start as the entry point to the kernel and the
	# bootloader will jump to this position once the kernel has been loaded. It
	# doesn't make sense to return from this function as the bootloader is gone.
	.section .text
	.global _start

	.type terminal_init @function
terminal_init:
	push ebp
	mov ebp, esp

    mov eax, 0

foreach_height:
    cmp eax, VGA_HEIGHT * VGA_WIDTH
    jge foreach_done

    mov WORD PTR [TERMINAL_BUFFER + 2*eax], (((0 << 4) | 2) << 8) | 'z'

    inc eax
    jmp foreach_height
    
foreach_done:
	    
	leave
	ret
	    
    .type _start, @function
_start:
	# To set up a stack, we simply set the esp register to point to the top of
	# our stack (as it grows downwards).
	mov esp, stack_top
	mov ebp, esp

    call terminal_init

	cli
.Lhang:
	hlt
	jmp .Lhang

	# Set the size of the _start symbol to the current location '.' minus its start.
	# This is useful when debugging or when you implement call tracing.
	.size _start, . - _start