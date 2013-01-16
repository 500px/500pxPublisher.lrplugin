#The 500px Publisher for Adobe Photoshop Lightroom®#

Get the 500px Publisher for effortless portfolio management. With features like two-way sync, ability to read and write comments, view all your stats  and more. Now you will have more time for shooting.  

To try 500px Publisher for, checkout http://500px.com/lightroom



### QUICK START
1. Clone the repo: git clone git://github.com/500px/500pxPublisher.lrplugin
2. Edit **CONSUMER_KEY**, **CONSUMER_SECRET** and **SALT** variables in **500pxAPI.lua**
3. Copy **500pxPublisher.lrplugin** directory into Lightroom plugins 
or Add the plugin thought *Lightroom Plug-in Maganger*

_(You can refer to User Guide at http://http://500px.com/lightroom)_


### CONTRIBUTE
Please pull request your changes, bug fixes. Thanks!



### HOW TO BUILD
Download and install Lua Compiler http://www.lua.org/download.html
We suggest to use Lua 5.1.4 for 32-bit architectures <a href="#get-a-32-bit-version-of-lua">(to get lua compiler for 32-bit architectures)</a>
(Files compiled with 32bit compiler will perfectly work on 32bit and 64bit, while files compiled with 64bit compiler will only work on 64bit computers and not on 32bit arcitecture)



### LICENSE
Licensed under the terms of the <a href="http://opensource.org/licenses/GPL-3.0">General Public License (GNU)</a>.

-----------------------

### GET A 32-BIT VERSION OF LUA
1. Download the Lua source from http://www.lua.org/download.html
2. Patch LUA_SOURCE/src/Makefile to make it 32-bit
```bash
    # Change this line
    macosx:
    -  	$(MAKE) all MYCFLAGS=-DLUA_USE_LINUX MYLIBS="-lreadline"
    + 	$(MAKE) all MYCFLAGS="-DLUA_USE_LINUX -arch i386" MYLIBS="-arch i386 -lreadline"

    # If you are having trouble compiling this because of 
    # readline, try removing '-lreadline'
```

3. Make and install Lua:
````bash
    make macosx
    sudo make install
```