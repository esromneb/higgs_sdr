# Meteor
This is a dashboard and or a Meteor example project

# Meteor Install
This is REQUIRED to run this example.
My install process on Ubuntu
```bash

curl https://install.meteor.com/ | sh
```


# Project install
Get the repo like normal...
```bash
git clone git@github.com:siglabsoss/higgs-dashboard.git
cd higgs-dashboard
nvm i 10
meteor npm install @babel/runtime@7.0.0-beta.55
meteor
```


# My first meteor Project
Try this yourself with a different name, meteor is very easy to get started with:

```bash

meteor create projname
cd projname
nvm i 10
meteor npm install @babel/runtime@7.0.0-beta.55
meteor
```

After this, meteor should boot (or it will give errors).  Open chrome and visit http://localhost:3000/ and you will see your app



#junk

```bash



Collection.update({_id: doc._id}, {$set: {field: value}})


// Delete them all

// RE.remove(RE.find().fetch()[0]._id)

// RE.remove(RE.find().fetch()[0]._id)


// example add one:
// 
// RE.insert({name:"sigcarrier013",info:"in memory on pc",state:4,stateColor:"#ff0000"});




```


# For Windows
Henry's untested install process on Windows
```bash
//install chocolatey using an admin rights cmd prompt
@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))" && SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
//use chocolatey to install meteor
choco install meteor
```
