echo "Setting hardware type to Tread..."
adb shell settings put global peloton_platform prism
adb shell am broadcast -a com.onepeloton.activity.SET_HARDWARE --es "hardware_type" "prism"
adb shell touch /sdcard/.HomeInstallerDone
adb shell touch /sdcard/.enablePrismSimulator
echo "Rebooting..."
adb reboot
echo "Tread hardware ready."