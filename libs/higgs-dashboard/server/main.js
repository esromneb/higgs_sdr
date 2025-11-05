import { Meteor } from 'meteor/meteor';

import '../collections/collections.js'
import './methods.js'
import '../lib/naked_functions.js'

import '/imports/startup/both'; 

// var mongoUUIDLookup = {};

var reUUIDLookup = {};

var smodemUUIDLookup = {};

var vectorUUIDLookup = {};


function inSmodemRange(uuid) {
    if( uuid >= 2000000 && uuid < 3000000 ) {
        return true;
    } else {
        return false;
    }
}

function inControlRange(uuid) {
    if( uuid >= 1000000 && uuid < 2000000 ) {
        return true;
    } else {
        return false;
    }
}

function inVectorRange(uuid) {
    if( uuid >= 3000000 && uuid < 4000000 ) {
        return true;
    } else {
        return false;
    }
}

function inRadioEstimateRange(uuid) {
    if( uuid >= 0 && uuid < 1000000 ) {
        return true;
    } else {
        return false;
    }
}


function inLogRange(uuid) {
    var _b = 4000000;
    if( uuid >= _b && uuid < _b+1000000 ) {
        return true;
    } else {
        return false;
    }
}



function mongoForUUID(uuid) {

    if(uuid in reUUIDLookup) {
        return reUUIDLookup[uuid];
    }

    if(uuid in smodemUUIDLookup) {
        return smodemUUIDLookup[uuid];
    }

    if(uuid in vectorUUIDLookup) {
        return vectorUUIDLookup[uuid];
    }

    if ( uuid == 4000000 ) {
        return uuid;
    }

    return null;


    // switch(uuid) {
    //   case 3:
    //     return "tjw8uN78p4SPuwgNw";
    //     break;
    // }

    // return null;
}

// returns non zero if we did something
function consumeControlForUUID(uuid) {
    switch(uuid) {
      case 1000001:
        console.log("New client connected");
        return uuid;
        break;
    }

    return 0;
}

var string_buffer = "";


function debugString(s) {
    var o = "";
    for (var i = 0; i < s.length; i++) {
        o += s.charCodeAt(i) + " ";
    }

    console.log(o);
}


function executeCustomDDPUpdate(as_str) {

    if( as_str.length === 0) {
      return;
    }

    try {
        var o = JSON.parse(as_str);
    } catch (err) {
        console.log("that one was bad json (" + as_str.length + "): " + as_str);
        return;
    }

    // console.log(o);

    var uuid;
    if( Array.isArray(o) && 'u' in o[0] ) {
      uuid = o[0].u;
    } else {
        try {
              console.log("something was wrong with that one" +
               " " + Array.isArray(o) + 
               " " +  o[0] +
               " " + o[0].u +
               " " +  o[1]);
        }
        catch(err) {
            console.log("something was wrong with that one" + as_str);
        }

      return;
    }

    var control_messsage = consumeControlForUUID(uuid);

    if(control_messsage) {
      // this message is done
      // console.log("finished with control message");
      return;
    }

    // after this part we assume something valud

    // console.log("checking uuid:" + uuid);
    var cached_id = mongoForUUID(uuid);

    if( cached_id === null ) {
      console.log("couldn't find that id " + o[0].u);
      return;
    }
    // console.log("  " + cached_id);





    // var command_text = o[1];
    // try {
    //     var o_from_client = JSON.parse(command_text);
    // } catch (err) {
    //     console.log("The command text was bad json");
    //     return;
    // }
    


    // var o_from_client = JSON.parse(command_text);


    // var cached_id = "tjw8uN78p4SPuwgNw";

    // var from_client = "{ \"$set\": { \"state\": 21 } }";

    // console.log(o[1]);

    // console.log("Got to execute on " + cached_id);

    if(inSmodemRange(uuid)) {
        // console.log("Using Smodem Collection");
        SModem.update(cached_id, o[1]);

    } else if(inRadioEstimateRange(uuid))  {
        // console.log("Using RE Collection");
        RE.update(cached_id, o[1]);

    } else if(inVectorRange(uuid)) {
        // console.log("Using Vector Collection");
        Vectors.update(cached_id, o[1]);
    } else if(inLogRange(uuid)) {
        Logs.insert(o[1]);
    }

}


var net = Npm.require('net');
// , dataStream = net.createConnection(10008,"192.168.1.63");
// dataStream.setEncoding('utf8');
// dataStream.on('data', function(data) {
//     var line = data.trim();
//     Messages.insert({name:"line",message: line, time:Date.now()});
// });

var socket2;

// ..set- and fire up a tcp server..
var server = net.createServer( Meteor.bindEnvironment( function ( socket ) {
  // ..with a listener that processes the commands..
  socket2 = socket;
  socket.addListener( "data", Meteor.bindEnvironment( function ( data ) {
        // console.log("called addListener(data) ");

       as_str = data.toString('ascii');
       // console.log(as_str);

       string_buffer += as_str;

       // console.log("before, buffer:");
       //      console.log(string_buffer);
       //      debugString(string_buffer);

       //  console.log("------------");

       var largest_slice = null;
       var prev_slice = 0;
       
       for (var i = 0; i < string_buffer.length; i++) {
          if( string_buffer.charAt(i) == "\0" ) {
            // console.log("found zero " + i);
            var slc = string_buffer.slice(prev_slice, i);
            // console.log();
            // console.log("slice: " + prev_slice + " " + i );
            // console.log();
            // console.log();
            // console.log(slc);
            // debugString(slc);
            executeCustomDDPUpdate(slc);
            largest_slice = i;
            prev_slice = i+1;
          }
        }

        // if(largest_slice === null) {
        //     executeCustomDDPUpdate(string_buffer);
        //     string_buffer = "";
        // }

        if(largest_slice !== null) {
            string_buffer = string_buffer.slice(largest_slice+1);
            // console.log("after, buffer:");
            // console.log(string_buffer);
            // debugString(string_buffer);
            // console.log(typeof string_buffer);
        }


    // ..working with collections now just works!

  } ) );
} ) ).listen(10008, '0.0.0.0');




// var zmq = require('zeromq');
// zmq_sock_sub = zmq.socket('sub'); // sub does bind
// zmq_sock_pub = zmq.socket('pub');


// var bind_address = "tcp://192.168.1.63:10008";
//   zmq_sock_sub.bindSync(bind_address);
//   console.log(bind_address);



//   zmq_sock_sub.subscribe('?');
//   zmq_sock_sub.subscribe('@0');

//   zmq_sock_sub.on('message', function(topic, message) {
// 	  console.log('received a message related to:', topic, 'containing message:', message);
// 	});

//   zmq_sock_pub.connect('tcp://192.168.1.63:10005');



//   zmq_sock_pub.send("?hi");

function forceInsertStarters() {

    var requied = [0,1];

    for (var key in requied) {
        var value = requied[key];

        var cnt = RE.find({array_index:value}).count();
        if(cnt == 0) {
            RE.insert({array_index:value});
        }


        var got = RE.find({array_index:value}).fetch()[0];
        console.log("Radio Estimate array_index: " + value + " key: " + got._id);

        reUUIDLookup[value] = got._id;

    }

    var req2 = [2000000];

    for (var key in req2) {
        var value = req2[key];

        var cnt = SModem.find({array_index:value}).count();
        if(cnt == 0) {
            SModem.insert({array_index:value});
        }

        var got = SModem.find({array_index:value}).fetch()[0];
        console.log("SModem array_index: " + value + " key: " + got._id);

        smodemUUIDLookup[value] = got._id;
    }

    var req3 = [3000000, 3000001, 3000002, 3000003,
                3001000, 3001001, 3001002, 3001003];

    for (var key in req3) {
        var value = req3[key];

        var cnt = Vectors.find({array_index:value}).count();
        if(cnt == 0) {
            Vectors.insert({array_index:value});
        }

        var got = Vectors.find({array_index:value}).fetch()[0];
        console.log("Vectors array_index: " + value + " key: " + got._id);

        vectorUUIDLookup[value] = got._id;
    }


    // mongoUUIDLookup


}


Meteor.startup(() => {
  // code to run on server at startup
  forceInsertStarters();
  
});



// Router.route('/users',{where: 'server'})
//     .get(function(){
//         this.response.setHeader('Content-Type','application/json');
//         this.response.end(JSON.stringify({"a":"b"}));
//     })


// Router.configure({
//     layoutTemplate: 'thisPageLeftBlank'
// });



if (Meteor.isServer) {
  // Meteor.startup(function () {
  //   if (Circles.find().count() === 0) {
  //     Circles.insert({data: [5, 8, 11, 14, 17, 20]});
  //   }
  // });

  // Meteor.setInterval(function () {
  //   var newData = _.shuffle(Circles.findOne().data);
  //   Circles.update({}, {data: newData});
  // }, 2000);

    Meteor.methods({

        clearLog: function() {
            while(Logs.find().count()) {
               var id = Logs.findOne()._id;
               Logs.remove(id);
           }
           //some stuff
           return 0;
        },


        keyDirection: function(key, dir) {
            // console.log("key direction: " + key + " " + dir);
            var o = [{u:1},{'$set':{'k':key,'d':dir}}];
            socket2.write(JSON.stringify(o));
            // socket2.write("\n");

            // var buf = Buffer.from('x');
            // buf[0] = 0;
            var buf = new Buffer([0x0]);
            socket2.write(buf);


            // var temp = [{u:1},{'$set':{'k':"foo bar bro",'d':dir}}];
            // socket2.write(JSON.stringify(temp));
            // socket2.write(buf);

        },

        controlButton: function(buttonDataset, altData) {
            console.log('controlButton()');
            console.log(buttonDataset);
            console.log(altData);
            var was_ok = false;
            var uid = 1000;
            var final;
            if(buttonDataset && buttonDataset['key'] && buttonDataset['value'] && buttonDataset['where']) {
                var key = buttonDataset['key'];
                var val = buttonDataset['value'];

                var key_path = key.split('.');
                console.log(key);
                console.log(key_path);
                console.log(val);


                if( val.indexOf('int') === 0 ) {
                    var valb = val.replace(/int\(/g, '');
                    var valc = valb.replace(/\)/g, '');
                    var vald = parseInt(valc);
                    final = [{u:uid},{k:key_path, v:vald, t:'int'}];
                    was_ok = true;
                }
                if( val.indexOf('double') === 0 ) {
                    var valb = val.replace(/double\(/g, '');
                    var valc = valb.replace(/\)/g, '');
                    var vald = parseFloat(valc);
                    final = [{u:uid},{k:key_path, v:vald, t:'double'}];
                    was_ok = true;
                }
                if( val.indexOf('string') === 0 ) {
                    var valb = val.replace(/string\(/g, '');
                    var valc = valb.replace(/\)/g, '');
                    final = [{u:uid},{k:key_path, v:valc, t:'string'}];
                    was_ok = true;
                }
                if( val.indexOf('bool') === 0 ) {
                    var valb = val.replace(/bool\(/g, '');
                    var valc = valb.replace(/\)/g, '');
                    var vald = valc.toLowerCase();
                    console.log(vald);
                    var vale;
                    if( vald === 'false' ) {
                        vale = false;
                        was_ok = true;
                    }
                    if( vald === 'true' ) {
                        vale = true;
                        was_ok = true;
                    }

                    if( was_ok ) {
                        final = [{u:uid},{k:key_path, v:vale, t:'bool'}];
                    }
                }
            }

            if(buttonDataset && buttonDataset['key'] && buttonDataset['fromId'] && buttonDataset['fromIdType'] && altData['value']) {
                var key = buttonDataset['key'];
                var type = buttonDataset['fromIdType']; // type
                var vala = altData['value'];

                var key_path = key.split('.');

                if( type.indexOf('int') === 0 ) {
                    var valb = parseInt(vala);
                    final = [{u:uid},{k:key_path, v:valb, t:'int'}];
                    was_ok = true;
                }
                if( type.indexOf('double') === 0 ) {
                    var valb = parseFloat(vala);
                    final = [{u:uid},{k:key_path, v:valb, t:'double'}];
                    was_ok = true;
                }
                if( type.indexOf('string') === 0 ) {
                    var valb = '' + vala;
                    final = [{u:uid},{k:key_path, v:valb, t:'string'}];
                    was_ok = true;
                }
                if( type.indexOf('bool') === 0 ) {
                    var valb = vala.toLowerCase();
                    console.log(valb);
                    var vale;
                    if( valb === 'false' ) {
                        vale = false;
                        was_ok = true;
                    }
                    if( valb === 'true' ) {
                        vale = true;
                        was_ok = true;
                    }
                    // last ditch effort, cast to an int and check truthiness
                    if(!was_ok) {
                        valc = parseInt(vala);
                        if(valc) {
                            vale = true;
                        } else {
                            vale = false;
                        }
                        was_ok = true;
                    }

                    if( was_ok ) {
                        final = [{u:uid},{k:key_path, v:vale, t:'bool'}];
                    }
                }
            }

            if( !was_ok ) {
                console.log("Call to buttonDataset() didn't go well " + JSON.stringify(buttonDataset));
            } else {
                socket2.write(JSON.stringify(final));
                var buf = new Buffer([0x0]);
                socket2.write(buf);
            }

            
        }
    });

}