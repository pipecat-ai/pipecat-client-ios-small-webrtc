URL_BASE_PATH=$1

# clean the temp dir
rm -rf ./tmpDocs

# create the docs
xcodebuild docbuild -scheme 'PipecatClientIOSSmallWebrtc' -destination "generic/platform=iOS" -derivedDataPath ./tmpDocs

# convert the doc archive for static hosting
$(xcrun --find docc) process-archive transform-for-static-hosting \
./tmpDocs/Build/Products/Debug-iphoneos/PipecatClientIOSSmallWebrtc.doccarchive \
--output-path ./tmpDocs/htmldoc \
--hosting-base-path $URL_BASE_PATH
# In case we need to change the host path
# more details here: https://www.createwithswift.com/publishing-docc-documention-as-a-static-website-on-github-pages/
# --hosting-base-path URL_BASE_PATH

