//server-side code
Meteor.publish('radio_estimates', () => {
  return RadioEstimates.find({ approved: true })
})