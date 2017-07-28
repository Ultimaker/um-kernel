setenv bootargs console=tty0 root=/dev/${ROOT_DEV} ro rootwait rootfstype=${ROOT_FS} console=ttyS0,115200 earlyprintk
setenv fdt_high 0xffffffff
${BOOTSPLASH_COMMANDS}

setenv article_num_r 0x43300000
setenv article_rev_r 0x43300004

# Load the article and revision number, these are in different byte order, so we need to swap them while reading.
i2c dev 1
i2c read 0x51 0 1 0x43300003
i2c read 0x51 1 1 0x43300002
i2c read 0x51 2 1 0x43300001
i2c read 0x51 3 1 0x43300000
i2c read 0x51 4 1 0x43300007
i2c read 0x51 5 1 0x43300006
i2c read 0x51 6 1 0x43300005
i2c read 0x51 7 1 0x43300004

setexpr.l article_number *${article_num_r}
setexpr.l article_rev *${article_rev_r}
echo Article number: ${article_number}-${article_rev}

# Build the possible dtb list from the article numbers with a fallback.
# We fall back to the v1 electronics with display right now, as these are most common, and required for the production installer software.
setenv dtb_list ${article_number}-${article_rev}.dtb ${article_number}.dtb um3v1-128x64-oled.dtb bare-lime2.dtb sun7i-a20-opinicus_emmc_v1.dtb

load mmc 0 0x46000000 uImage-sun7i-a20-opinicus_v1
for dtb in ${dtb_list}; do
    if load mmc 0 0x49000000 ${dtb}; then
        bootm 0x46000000 - 0x49000000
    fi
done
echo "No devicetree found!"
sleep 5
reset
