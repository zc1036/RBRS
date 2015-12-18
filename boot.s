
	.intel_syntax noprefix

	// Declare constants used for creating a multiboot header.
	.set ALIGN,    1<<0             // align loaded modules on page boundaries
	.set MEMINFO,  1<<1             // provide memory map
	.set FLAGS,    ALIGN | MEMINFO  // this is the Multiboot 'flag' field
	.set MAGIC,    0x1BADB002       // 'magic number' lets bootloader find the header
	.set CHECKSUM, -(MAGIC + FLAGS) // checksum of above, to prove we are multiboot
	.set VGA_WIDTH, 80
	.set VGA_HEIGHT, 25
    .set TERMINAL_BUFFER, 0xB8000
    .set PAGE_SIZE, 0x1000

	// Declare a header as in the Multiboot Standard. We put this into a special
	// section so we can force the header to be in the start of the final program.
	// You don't need to understand all these details as it is just magic values that
	// is documented in the multiboot standard. The bootloader will search for this
	// magic sequence and recognize us as a multiboot kernel.
	.section .multiboot
	.align 4
	.long MAGIC
	.long FLAGS
	.long CHECKSUM

	// Currently the stack pointer register (esp) points at anything and using it may
	// cause massive harm. Instead, we'll provide our own stack. We will allocate
	// room for a small temporary stack by creating a symbol at the bottom of it,
	// then allocating 16384 bytes for it, and finally creating a symbol at the top.
	.section .bootstrap_stack, "aw", @nobits
stack_bottom:
	.skip 16384 // 16 KiB
stack_top:

    .section .page_tables, "aw", @nobits
PAGE_TABLES_BASE:    
    .skip 0x4000

    .data
GDT:                                // Global Descriptor Table (64-bit).
NULL_DESC:                          // The null descriptor.
    .word 0                         // Limit (low).
    .word 0                         // Base (low).
    .byte 0                         // Base (middle)
    .byte 0                         // Access.
    .byte 0                         // Granularity.
    .byte 0                         // Base (high).
CODE_DESC:                          // The code descriptor.
    .word 0xFFFF                    // Lower (lower 16)
    .word 0                         // Base (lower 16)
    .byte 0                         // Base (middle 8)
    .byte 0b10011010                // Access byte (bits left->right: 0=selector present?, 1:2=privilege ring, 3=always 1, 4=executable?, 5=allow jump from lower ring?, 6=code readable?, 7=accessed [we always set to 0, CPU sets to 1]).
    .byte 0b11101111                // Combo (bits left->right: 0=granularity [1 is 4kb page, 0 is byte], 1=size bit [0 is 16 bit, 1 is 32 bit], 2=64 bit?, 3=always 0, 4:7=upper bits of limit)
    .byte 0                         // Base (high 8).
DATA_DESC:                          // The data descriptor.
    .word 0xFFFF                    // Lower (lower 16)
    .word 0                         // Base (lower 16)
    .byte 0                         // Base (middle 8)
    .byte 0b10010010                // Access byte (bits left->right: 0=selector present?, 1:2=privilege ring, 3=always 1, 4=executable?, 5=segment grows toward lower addresses?, 6=data writable?, 7=accessed [we always set to 0, CPU sets to 1]).
    .byte 0b11001111                // Combo (bits left->right: 0=granularity [1 is 4kb page, 0 is byte], 1=size bit [0 is 16 bit, 1 is 32 bit], 2:3=always 0, 4:7=upper bits of limit)
    .byte 0                         // Base (high 8).
GDT_DESC:                           // The GDT-pointer.
    .word . - GDT - 1               // Limit.
    .long GDT                       // Base.
    .long 0                         // For use as a 64 bit GDT

IDT:    
IVT_DESC:
    .word . - IDT - 1
    .long IDT

	.section .text
    .code32
	
	.global _start
    .type _start, @function
_start:
    cli
	mov esp, stack_top
	mov ebp, esp

    ////// BEGIN ENTRANCE TO LONG MODE

	//// Set the a20 line if neccessary, skip if not
	in al, 0x92
	test al, 2
	jnz .a20_already_set
	or al, 2
	and al, 0xFE
	out 0x92, al
.a20_already_set:
	
    //// Clear (zero out) the page table structures
    lea edi, [PAGE_TABLES_BASE] // Set the destination index to 0x1000.
    xor eax, eax                // Nullify the A-register.
    mov ecx, 4096               // Set the C-register to 4096.
    rep stosd                   // Clear the memory.
    lea edi, [PAGE_TABLES_BASE] // Set the destination index to control register 3.
                                // cr3 points to the root of the page table hierarchy.

    //// Set up one page
    // The lower two bits are flags whether the page is mapped and readable/writable
    mov eax, edi
    add eax, PAGE_SIZE | 0b11
    mov DWORD PTR [edi], eax
    add edi, PAGE_SIZE
    add eax, PAGE_SIZE
    mov DWORD PTR [edi], eax
    add edi, PAGE_SIZE
    add eax, PAGE_SIZE
    mov DWORD PTR [edi], eax
    add edi, PAGE_SIZE // edi now points to the actual page table

    //// Identity-map the first the first two megabytes of address space
    mov ebx, 0x00000003          // The value in the key-value page table, incremented by one page on each iteration.
    mov ecx, 512                 // Loop 512 times
 
.set_page_table_entry:
    mov DWORD PTR [edi], ebx // Set the page entry
    add ebx, PAGE_SIZE       // Increment value a page
    add edi, 8               // Each entry is 8 bytes
    loop .set_page_table_entry

    //// Enable PAE paging
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    //// put the pointer to the page tables in the page table pointer register (cr3)
    lea edi, [PAGE_TABLES_BASE]
    mov cr3, edi

    //// Enable paging and protected mode
    lgdt [GDT_DESC]              // Load the 64-bit global descriptor table.
	
    //// Set LM (long mode) bit in the model-specific register
    mov ecx, 0xC0000080          // Set the C-register to 0xC0000080, which is the EFER MSR.
    rdmsr                        // Read from the model-specific register.
    or eax, 1 << 8               // Set the LM-bit which is the 9th bit (bit 8).
    wrmsr                        // Write to the model-specific register.

    //// Enable paging
    mov eax, cr0
    or eax, (1 << 31) | 1
    mov cr0, eax

    ljmp (CODE_DESC - GDT), .long_mode

.code64
.long_mode:
    mov WORD PTR [TERMINAL_BUFFER], (((0 << 4) | 2) << 8) | 'z'
    jmp halt64

halt64:
    hlt
	jmp halt64
