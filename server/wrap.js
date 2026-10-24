// Lets async route handlers pass their errors to Express.
module.exports = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
