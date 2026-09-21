echo "Setting hardware type to Tread..."
adb shell settings put global peloton_platform aurora
adb shell am broadcast -a com.onepeloton.activity.SET_HARDWARE --es "hardware_type" "aurora"
adb shell touch /sdcard/.HomeInstallerDone
adb shell touch /sdcard/.enableAuroraSimulator
echo "Rebooting..."
adb reboot
echo "Tread hardware ready."