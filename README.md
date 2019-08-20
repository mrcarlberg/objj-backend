# objj-backend

This is a backend written in Objective-J running on node.js for the [LightObject](https://github.com/mrcarlberg/LightObject) framework.

## Install

You have to have node.js version 4.2 or later. You also need Postgressql database installed too.

To install the backend use ```npm```

```npm install objj-backend```

From the installed directory do ```bin/objj main.j --help``` to get all options

A typical start of the backend looks like this:
```bin/objj main.j -d <database name> -u <database username> -v -V -A Model.xcdatamodeld```

This means verbose is on and it will log all sql etc with ```-v```, validate the database against the model ```-V```, alter the database so it corresponds to the model ```-A``` and the path to the model file is ```Model.xcdatamodeld```.

To set up an Apache webserver I use ```ProxyPass``` and have added one line to my Apache config file:
```ProxyPass /backend http://localhost:1337```

More documentation is coming shortly....
