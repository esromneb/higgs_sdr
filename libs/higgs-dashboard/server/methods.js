Meteor.startup(function () {
	Meteor.methods({

        trigger : function()
        {
            console.log('hiiasdf');
            return "ok";
        }

       });
});