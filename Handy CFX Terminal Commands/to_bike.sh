echo "Setting hardware type to Titan..."
adb shell settings put global peloton_platform titan
adb shell am broadcast -a com.onepeloton.activity.SET_HARDWARE --es "hardware_type" "titan"
adb shell touch /sdcard/.HomeInstallerDone
adb shell rm -rf /sdcard/.enablePrismSimulator
adb shell rm -rf /sdcard/.enableAuroraSimulator
echo "Rebooting..."
adb reboot
echo "Bike hardware ready."
adb shell am broadcast -a onepeloton.intent.action.AUTOMATION_FAKE_DATA --es onepeloton.intent.extra.PLATFORM prism --ei onepeloton.intent.extra.FAKE_DATA_STATE 0
