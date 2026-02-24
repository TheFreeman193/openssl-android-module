MINAPI="{0}"
MAXAPI="{1}"
MINVER="{2}"
MAXVER="{3}"
MODNAME="{4}"
MODID="{5}"

[ -z "$MAGISK_VER" -a -z "$KSU_VER" -a -z "$APATCH_VER" ] && abort "The $MODNAME module only works with Magisk, KernelSU, and APatch."
[ -z "$MODPATH" -o ! -d "$MODPATH" ] && abort "MODPATH env var not set or MODPATH doesn't exist. Cannot continue."

[ -z "$API" ] && API="$(getprop ro.build.version.sdk)"
[ -z "$API" ] && abort "Couldn't determine Android API level."
[ -z "$ABI" ] && ABI="$(getprop ro.system.product.cpu.abilist | cut -d',' -f1)"
[ -z "$ABI" ] && abort "Couldn't determine Android ABI."

ui_print "Device ABI=$ABI Android API level=$API"

[ "$API" -lt "$MINAPI" -o "$API" -gt "$MAXAPI" ] && abort "This build of the $MODNAME module doesn't include a binary for API level $API. Supported APIs: $MINAPI ($MINVER) to $MAXAPI ($MAXVER)."

[ ! -f "$MODPATH/bin/$ABI/openssl" ] && abort "This build of the $MODNAME module doesn't include a binary for ABI '$ABI'. Download the module ending '-$ABI.zip' or request a build for this architecture."

if [ "$API" -gt 24 -a -d "/product/bin" -o -d "/system/product/bin" ] && echo $PATH | grep -q -e '/product/bin$' -e '/product/bin:'; then
    TARGET="system/product/bin"
else
    TARGET="system/bin"
fi

CONFIG_TARGET="system/etc/ssl"

if [ ! -d "$MODPATH/$TARGET" ]; then
    ui_print "Creating overlay directory '$MODPATH/$TARGET'..."
    mkdir -p "$MODPATH/$TARGET" || abort "Unable to create overlay directory!"
fi

ui_print "Copying '$MODPATH/bin/$ABI/openssl' to overlay directory..."
cp -t "$MODPATH/$TARGET/" "$MODPATH/bin/$ABI/openssl" || abort "Unable to copy openssl binary!"

ui_print "Setting file mode on '$MODPATH/$TARGET/openssl'..."
set_perm "$MODPATH/$TARGET/openssl" root shell 0755 || ui_print "!! WARNING: Unable to set permissions on openssl binary. You may not be able to access it from non-privileged shells."

ui_print "Cleaning up module bin directory..."
rm -rf "$MODPATH/bin/"

if grep -q '-Universal.json' "$MODPATH/module.prop"; then
    ui_print "Change module update URL from Universal to $ABI..."
    sed -i "s/\(module-update-\)Universal\(.json\)/\1$ABI\2/" "$MODPATH/module.prop"
fi

if [ -d "/data/adb/modules/$MODID/ssl" ] && [ ! -f "/data/adb/modules/$MODID/remove" ]; then
    ui_print "Migrating SSL configuration from existing $MODID module..."
    ui_print "TIP: You can remove the old module first to get a clean config."
    cp -nt "$MODPATH/$CONFIG_TARGET" "/data/adb/modules/$MODID/$CONFIG_TARGET/*"
    cp -ft "$MODPATH/$CONFIG_TARGET" "/data/adb/modules/$MODID/$CONFIG_TARGET/openssl.cnf"
    set_perm_recursive "$MODPATH/$CONFIG_TARGET" root shell 0755 0755 || ui_print "!! WARNING: Unable to set permissions on '$MODPATH/$CONFIG_TARGET'. OpenSSL may not be able to access config files from non-privileged shells."
else
    ui_print "TIP: You can edit /data/adb/modules/$MODID/$CONFIG_TARGET/openssl.cnf to change OpenSSL's default CA config, or set \$OPENSSL_CONFIG to a custom path."
fi

[ -f "/$TARGET/openssl" -a ! -f "/data/adb/modules/$MODID/$TARGET/openssl" ] && ui_print "!! WARNING: An openssl binary already seems to exist in /$TARGET and will be inaccessible while this module is installed !!"

for BINPART in system product vendor system_ext system_dlkm vendor_dlkm vendor/odm vendor/odm_dlkm; do
    for BINDIR in bin xbin sbin; do
        [ "/$BINPART/$BINDIR" != "/$TARGET" -a "/system/$BINPART/$BINDIR" != "/$TARGET" -a -f "/$BINPART/$BINDIR/openssl" ] && ui_print "!! WARNING: An openssl binary already seems to exist in '/$BINPART/$BINDIR'. This file might take precedence over the module's openssl, depending on \$PATH order."
    done
done

ui_print "Done! openssl should be available in /$TARGET after a reboot."
