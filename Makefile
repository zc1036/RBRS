
BOOTSTRAP_ASM=boot.s
BOOTSTRAP_OBJ=boot.o
LD_SCRIPT=linker.ld
ISO=rbrs.iso
ISODIR=isodir
BIN=$(ISODIR)/boot/rbrs.bin
GRUB_CFG=grub.cfg

$(ISO): $(BIN)
	grub-mkrescue -o $(ISO) $(ISODIR)

$(BIN): $(BOOTSTRAP_OBJ)
	$(LD) -T linker.ld -m elf_i386 -nostdlib $(BOOTSTRAP_OBJ) $(INIT_OBJ) -o $(BIN)

$(BOOTSTRAP_OBJ): $(BOOTSTRAP_ASM)
	$(AS) $(BOOTSTRAP_ASM) -o $(BOOTSTRAP_OBJ)

.PHONY: clean qemu

qemu: $(ISO)
	qemu-system-x86_64 -cdrom rbrs.iso

clean:
	rm -f $(BOOTSTRAP_OBJ) $(ISO) $(BIN)
