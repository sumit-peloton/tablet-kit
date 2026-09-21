echo "Setting hardware type to Row..."
adb shell settings put global peloton_platform caesar
adb shell am broadcast -a com.onepeloton.activity.SET_HARDWARE --es "hardware_type" "caesar"
adb shell touch /sdcard/.HomeInstallerDone
adb shell rm -rf /sdcard/.enablePrismSimulator
adb shell rm -rf /sdcard/.enableAuroraSimulator
echo "Rebooting..."
adb reboot
echo "Row hardware ready."