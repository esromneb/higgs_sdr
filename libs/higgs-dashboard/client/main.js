import { Template } from 'meteor/templating';
import { ReactiveVar } from 'meteor/reactive-var';

import './main.html';

// Meteor.subscribe('radio_estimates');

import '/imports/startup/client';
import '/imports/startup/both';

import '../collections/collections.js'



Template.hello.onCreated(function helloOnCreated() {
  // counter starts at 0
  this.counter = new ReactiveVar(0);
});

Template.hello.helpers({
  counter() {
    return Template.instance().counter.get();
  },
});

Template.hello.events({
  'click button'(event, instance) {
    // increment the counter when button is clicked
    instance.counter.set(instance.counter.get() + 1);
  },
});

Template.hello2.events({
  'click button'(event, instance) {
    Meteor.call("clearLog", function(){});
  },
});

Template.controlButtons.events({
  'click button'(event, instance) {
    // Meteor.call('controlButton', event.target.dataset);

    console.log(event.target.dataset);
    if( event.target.dataset
        && event.target.dataset["fromId"] 
        && event.target.dataset["fromIdType"] ) {
        // console.log(event.target.dataset["fromId"]);
        // console.log(Template.find('#fooInput'));
        // console.log($('#fooInput'));
        // console.log($('#fooInput')[0].value);
        var sel = event.target.dataset["fromId"];
        Meteor.call('controlButton', event.target.dataset, {value:$('#'+sel)[0].value});
    } else {
        Meteor.call('controlButton', event.target.dataset, null);
    }
    // console.log(event.target.dataset['key']);
    // console.log(event.target.dataset['value']);
  },
});


Template.forColor = function() {

}

Template.RadioEstimateWildcardTemplate.reObject = function() {
    var wc = [];
    wc = RE.find().fetch().concat(SModem.find().fetch());
    // for( let x of wc ) {
    //   if( x && x.sto && typeof x.sto.sto_delta !== 'undefined' ) {
    //     x.sto.sto_delta2 = x.sto.sto_delta * ((1/0.041)/0.75/0.65)*0.84;
    //     console.log('delta: ' + x.sto.sto_delta2);
    //   }
    // }
    return wc;
}

// Template.RadioEstimateWildcardTemplate.keys = function() {
//   return ['array_index', ]
// }

Template.RadioEstimateWildcardTemplate.asJson = function() {
  return JSON.stringify(this);
}


Template.RadioEstimateTemplate.reObject = function() {

    let o = RE.find().fetch();

    for(let i = 0; i < o.length; i++) {
      if(o[i] && o[i].sto && o[i].sto.sto_estimated ) {
        console.log(o[i].sto.sto_estimated);
        o[i].sto.sto_adjustment = o[i].sto.sto_estimated / 256;
      }
    }

    return o;

    // return Chats.find({}, {
    //     sort: {timestamp: 1},
    //     limit: 1000
    // });
}

Template.RadioEstimateTemplate.lookupState = function() {
  // see lib/lookup*
  return lookupEventDspFsmStates(this.fsm.state);
}

Template.RadioEstimateTemplate.stateColor = function () {
  var st = this.fsm.state;
  var out = hsvColorForStateNumber(100, st);
  return out;
}



Template.RadioEstimateTemplate.helpers({
    helperGetVis() {
        // console.log(this);
        // this is a RE object
        var show_which = 1;

        var tag;
        switch(this.array_index) {
            case 0:
                tag = 3000000 + 0    + show_which;
                break;
            case 1:
                tag = 3000000 + 1000 + show_which;
                break;
            default:
                return;
        }
        // console.log("GEtVis helper " + tag);

        return Vectors.findOne({array_index:tag});
        // return Vectors.find({array_index:{'$in':[3000000,3000001]}});

    },
    helperGetVis2() {
        // console.log(this);
        // this is a RE object
        var show_which = 0;

        var tag;
        switch(this.array_index) {
            case 0:
                tag = 3000000 + 0    + show_which;
                break;
            case 1:
                tag = 3000000 + 1000 + show_which;
                break;
            default:
                return;
        }
        // console.log("GEtVis helper " + tag);

        return Vectors.findOne({array_index:tag});
        // return Vectors.find({array_index:{'$in':[3000000,3000001]}});

    }
});






///
/// SModem template etc
/// 




Template.smodemTemplate.stateColor = function () {
  var st = this.fsm.state;
  var out = hsvColorForStateNumber(100, st);
  return out;
  return "#ff0000";
}

Template.smodemTemplate.smodemObject = function() {
    
    return SModem.find();


    // return Chats.find({}, {
    //     sort: {timestamp: 1},
    //     limit: 1000
    // });

}

Template.smodemTemplate.lookupState = function() {
  // see lib/lookup*
  return lookupEventDspFsmStates(this.fsm.state);
}





Template.RadioEstimateTemplate.chatMessages = function() {
// return Chats.find({}, {
//     sort: {timestamp: 1},
//     limit: 1000
// });
var o = {};
o['nic'] = 'asdf';
o['message'] = 'hello';
// o['stateColor'] = colorForStateNumber(1);
return [o,o];
};


Template.vectorTemplate.objects = function () {
    return Vectors.find();
}


  // Router.route('/foos/editor/:_id', function() {
  //      console.log('here');
  //      var item = Foos.findOne({_id: this.params._id});
  //      this.render('foo_editor', {data: item});
  // });

var log_results_limit = 25;

var log_lim = {limit: log_results_limit};

Template.allLogs.logs_0 = function () {
    var dl = 10;
    // return Logs.find({t:'rb'}, log_lim);
    return Logs.find({t:'rx'}, log_lim);
    // return [{c:"hi"}, {c:"ho"}];
}

Template.allLogs.logs_1 = function () {
    return Logs.find({t:'r0_rb'}, log_lim);
    // return [{c:"hi"}, {c:"ho"}];
}


Template.allLogs.logs_2 = function () {
    return Logs.find({t:'r1_rb'}, log_lim);
    // return [{c:"hi"}, {c:"ho"}];
}



/*


{{#each chatMessages}}
        <span class="singleRe"><strong>{{nic}}: </strong>{{message}}</span><br>
        {{/each}}


*/


// Delete them all

// RE.remove(RE.find().fetch()[0]._id)

// RE.remove(RE.find().fetch()[0]._id)

// SModem.remove(SModem.findOne()._id)


// example add one:
// 
// RE.insert({name:"sigcarrier013",info:"in memory on pc",state:4,stateColor:"#ff0000"});



if (Meteor.isClient) {

    // template with d3 will not render until this session is set
    vectors_found = 0;
    Vectors.find().observe({
        added: function (xyz) {
            vectors_found++;
            // console.log(vectors_found);
            if(vectors_found>7) {
                Session.set("canRenderVis", true);

            }

       }
    });
  
    Template.RadioEstimateTemplate.rendered = function() {
        Session.set("canRenderVis", false);
    }

    Template.RadioEstimateTemplate.debugCanRender = function() {
        return Session.get("canRenderVis");
    }




    Template.keyer.rendered = function () {


        this.$( '#keyEventInput' ).keydown(event => {
            console.log('down ' + event.key);
            Meteor.call('keyDirection', event.key, 'd');
            
            var elem = this.$('#keyStatus');

            var exist = elem.html();


            // causes cute double letter effect
            if( exist == event.key || exist[0] == event.key) {
                elem.append(event.key);
            } else {
                elem.html(event.key);
                
            }

            Meteor.setTimeout(
                function(){elem.html("")}
                , 500);

            // return false to prevent inputs from going 
            return false;
        }); 
        this.$( '#keyEventInput' ).keyup(event => {
            // console.log('down ' + event.key);
            Meteor.call('keyDirection', event.key, 'u');
        }); 



        // document.addEventListener('keydown', event => {
        //     // console.log('down ' + event.key);
        //     props.sock.send('{"type":"keydown","value":"' + event.key +'"}');
        // });

        // document.addEventListener('keyup', event => {
        //     // console.log('up ' + event.key);
        //     props.sock.send('{"type":"keyup","value":"' + event.key +'"}');
        // });
      
    }

    // void attach_key_handlers() {

    // }

    // var draw_mongo_id;

    // draw_mongo_id = "3aWeDTbFwHyGgg9v5"; // r0 angle sent
    // draw_mongo_id = "Jmd9c4W9Bji6ZcPbP"; // r0 observe

    // draw_mongo_id = "aXgP2FirSd95untjp"; // r1 angle sent


    // Tmplate.vis.getName = function() {
    //     return nameForVectorUid(1);
    // }

    Template.visSlim.forCopy = function() {
        // var _this = Vectors.findOne({array_index:this.render_with});
        // console.log("visSlim.forcopy");
        // console.log(this);
        // console.log(_this);
        // var ar = Vectors.find(draw_mongo_id).fetch()[0].vector;
        var ar = this.vector;
        return "a = [" + ar + "]";
        // return draw_mongo_id;
    }

    Template.visSlim.getNamee = function() {
        // console.log("getNamee  got ");
        // var ar = Vectors.find(draw_mongo_id).fetch()[0];
        var ar = this;
        var uid = JSON.stringify(ar.array_index);

        return nameForVectorUid(uid);
        // var ar = Vectors.find(draw_mongo_id).fetch()[0].vector;
        // return "a = [" + ar + "]";
        // return draw_mongo_id;
    }

    // Template.vis2.objects = function() {
    //     return Vectors.find({array_index:{'$in':[3000000,3000001]}});
    // }

    Template.visSlim.theSelector = function () {
        return 'vis_' + this.array_index;
    }


    Template.RadioEstimateTemplate.canRenderVis = function(){
      return Session.get("canRenderVis");
    }


  Template.visSlim.rendered = function () {
    var svg, width = 1000, height = 300;

    // console.log(RE);
    // console.log(Vectors.find().fetch());

    var xx = d3.time.scale()
    .rangeRound([0, width/1024]);

    var yy = d3.scale.linear()
    .rangeRound([height, 0]);


    // var yy = d3.svg.scaleLinear()
    // .rangeRound([height, 0]);
  //   var timeScale = d3.time.scale()
  // .domain([new Date(2016, 0, 1), new Date(2017, 0, 1)])
  //   .range([0, 700]);


    // console.log('Template.visSlim.rendered');
    // console.log(this);
    var a_selector = '#vis_' + this.data.array_index;
    // console.log(a_selector);

    let y_gain = gainForUid(this.data.array_index);

    // console.log(a_selector + ' gain ' + y_gain);

    var valueline = d3.svg.line()
    .x(function(d, i) { return xx(i); })
    .y(function(d, i) { return yy(y_gain*d/100); });

    // bottom fudge
    var b_fudge = 40;

    margin = {top: 0, right: 0, bottom: (height/2) + b_fudge, left: 20};

    tranlate_t = [margin.left,0];


    svg = d3.select(a_selector).append('svg')
      .attr("width", width + margin.left + margin.right)
        .attr("height", height + margin.top + margin.bottom)
    // .append("g")
        .attr("transform", 
              "translate(" + tranlate_t[0] + "," + tranlate_t[1] + ")")

        ;

    let prevMax = 3.14;


    // false is passed for the first render
    var drawCircles = function (update, _mongo_id) {
        // console.log("drawCircles " + _mongo_id);
        // console.log(this);

      // var data = this.data.vector;

      var data = Vectors.find(_mongo_id).fetch()[0].vector;

      let dataMax = 0;
      for( let x of data ) {
        let a = Math.abs(x);
        if(a > dataMax) {
          dataMax = a;
        }
      }

      if( dataMax < prevMax ) {
        dataMax = prevMax;
      }

      y_gain = gainForMax(dataMax);

      // console.log(a_selector + ' had max value of ' + dataMax + ' choosing gain of ' + y_gain);

      // var data = Circles.findOne().data;
      // var circles = svg.selectAll('circle').data(data);
      // console.log(circles);
      if (!update) {
        // console.log("no update");

        // Add the valueline path.
        svg.append("path")
            .attr("class", "line")
            .attr("d", valueline(data))
            .attr("class", "line")
            .style("stroke", function() { // Add dynamically
                return 'white'; })
            ;


      } else {
        // svg.remove();
        svg.selectAll("*").remove();
                svg.append("path")
            .attr("class", "line")
            .attr("d", valueline(data))
            .attr("class", "line")
            .style("stroke", function() { // Add dynamically
                return 'white'; })
            ;
        // console.log("yes update");
        // console.log(update);
        // circles = circles.transition();//.duration(1000);
      }
      // circles.attr('r', function (d) { return d; });
    };

    // console.log('setting up vector find ', draw_mongo_id);
    // console.log(this.data);
    var draw_this = this.data._id;
    Vectors.find(draw_this).observe({
      added: function (xyz) {
        
        x = d3.scale.ordinal()
          .domain(d3.range(xyz.vector.length))
          .rangePoints([0, width], 1);

          // call with false the first time
        drawCircles(false, draw_this);
      },
      changed: _.partial(drawCircles, true, draw_this)
    });
  };
} // if is client



Router.route('/', {
    template: 'thisPageLeftBlank'
});