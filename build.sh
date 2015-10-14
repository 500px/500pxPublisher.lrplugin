#!/bin/bash
BUILD_NUMBER='build-number'
SRC_DIR='../500pxPublisher.lrplugin'
BUILD_DIR='bin/500pxPublisher.lrplugin'
LUAC='luac'
BASEDIR='/Users/anurlybayev/workspace/500px/500pxPublisher.lrplugin'

cd $BASEDIR

version_raw=`cat $BUILD_NUMBER`
OIFS=$IFS
IFS='.'
version=($version_raw)
major=${version[0]}
minor=${version[1]}
#revision=${version[2]}
#build=${version[3]}
IFS=$OIFS

if [[ $1 == "major" ]]; then
    major=`expr $major + 1`
    minor='0'
#    revision='0'
#    build='0'
else
    minor=`expr $minor + 1`
#    revision='0'
#    build='0'
#elif [ $1 == "revision" ]; then
#    revision=`expr $revision + 1`
#    build='0'
#else
#    build=`expr $build + 1`
fi

mkdir -p $BUILD_DIR

rm -f $BUILD_DIR/*

echo -e "return {" > "$BUILD_DIR/Info.lua"
echo -e "\tLrSdkVersion = 4.0," >> "$BUILD_DIR/Info.lua"
echo -e "\tLrSdkMinimumVersion = 3.0," >> "$BUILD_DIR/Info.lua"
echo -e "\tLrToolkitIdentifier = \"com.500px.publisher\"," >> "$BUILD_DIR/Info.lua"
echo -e "\tLrPluginName = \"500px\"," >> "$BUILD_DIR/Info.lua"
echo -e "\tLrInitPlugin = \"PluginInit.lua\"," >> "$BUILD_DIR/Info.lua"
echo -e "\tLrPluginInfoUrl = \"http://500px.com/lightroom\"," >> "$BUILD_DIR/Info.lua"
echo -e "\tLrExportServiceProvider = {" >> "$BUILD_DIR/Info.lua"
echo -e "\t\ttitle = \"500px\"," >> "$BUILD_DIR/Info.lua"
echo -e "\t\timage = \"500px.png\"," >> "$BUILD_DIR/Info.lua"
echo -e "\t\tfile = \"500pxExportServiceProvider.lua\"," >> "$BUILD_DIR/Info.lua"
echo -e "\t}," >> "$BUILD_DIR/Info.lua"
echo -e "\tLrMetadataTagsetFactory = \"500pxTagset.lua\"," >> "$BUILD_DIR/Info.lua"
echo -e "\tLrMetadataProvider = \"500pxMetadataDefinition.lua\"," >> "$BUILD_DIR/Info.lua"
#echo -e "\tVERSION = { major=$major, minor=$minor, revision=$revision, build=$build }," >> "$BUILD_DIR/Info.lua"
echo -e "\tVERSION = { major=$major, minor=$minor }," >> "$BUILD_DIR/Info.lua"
echo -e "}" >> "$BUILD_DIR/Info.lua"

cp $SRC_DIR/* $BUILD_DIR

cd $BUILD_DIR

rm -f build.sh

for file in *.lua
do
    $LUAC -o $file $file
done

cd ..
#zip -r "500pxPublisher v$major.$minor.$revision.$build.zip" 500pxPublisher.lrplugin
zip -r "500pxPublisher_v$major.$minor.zip" 500pxPublisher.lrplugin

cd ..
#echo "$major.$minor.$revision.$build" > $BUILD_NUMBER
echo "$major.$minor" > $BUILD_NUMBER
