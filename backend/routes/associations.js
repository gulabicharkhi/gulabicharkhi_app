const express = require('express');
const mongoose = require('mongoose');
const Association = require('../models/Association');
const Tournament  = require('../models/Tournament');
const User        = require('../models/User');
const Notification = require('../models/Notification');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

const fail = (res, status, message, extra = {}) =>
  res.status(status).json({ success: false, message, ...extra });

const wrap = (label, fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (error) {
    console.error(`${label} error:`, error);
    if (!res.headersSent) fail(res, 500, 'Something went wrong. Try again.');
  }
};

// ==================== @GET /api/associations ====================
// Association tab - list of all associations
router.get('/', protect, wrap('Associations list', async (req, res) => {
  const associations = await Association.find({})
    .select('name state city logo sanctionedEvents members')
    .sort({ name: 1 });

  res.status(200).json({
    success: true,
    associations: associations.map((a) => ({
      id: a._id,
      name:   a.name,
      state:  a.state || '',
      city:   a.city  || '',
      logo:   a.logo  || null,
      memberCount:     a.members.filter((m) => m.status === 'approved').length,
      sanctionedEvents: a.sanctionedEvents || 0,
    })),
  });
}));

// ==================== @GET /api/associations/:id ====================
// Association detail page - officials, rule book
router.get('/:id', protect, wrap('Association detail', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid id');

  const assoc = await Association.findById(req.params.id)
    .select('-members'); // members list private hai
  if (!assoc) return fail(res, 404, 'Association not found.');

  res.status(200).json({
    success: true,
    association: {
      id:          assoc._id,
      name:        assoc.name,
      state:       assoc.state,
      city:        assoc.city,
      logo:        assoc.logo,
      email:       assoc.email,
      website:     assoc.website,
      officials:   assoc.officials,
      ruleBook:    assoc.ruleBook,
      sanctionedEvents: assoc.sanctionedEvents,
    },
  });
}));

// ==================== @GET /api/associations/page/home ====================
// Association Tab home - user ka standing + all associations + rule book sections
// App mein: "YOUR STANDING" + "AFFILIATED ASSOCIATIONS" + "OFFICIAL RULE BOOK"
router.get('/page/home', protect, wrap('Association home', async (req, res) => {
  const user = await User.findById(req.user._id).select('name federationId city');

  // Rule book - pehli association se ya hardcoded sections
  // Production mein: DB se lo
  const ruleBook = [
    { title: 'Match length & winning',      content: '' },
    { title: 'Approved kites & strings',    content: '' },
    { title: 'Cuts, near-misses & disputes',content: '' },
    { title: 'Player conduct',              content: '' },
    { title: 'Captain responsibilities',    content: '' },
  ];

  const associations = await Association.find({})
    .select('name state city logo sanctionedEvents members')
    .sort({ name: 1 });

  res.status(200).json({
    success: true,
    myStanding: {
      name:         user.name,
      federationId: user.federationId || `KA-${(user.city || 'JPR').slice(0, 3).toUpperCase()}—`,
      isRegistered: !!user.federationId,
    },
    associations: associations.map((a) => ({
      id:    a._id,
      name:  a.name,
      state: a.state || '',
      city:  a.city  || '',
      logo:  a.logo  || null,
      memberCount:     a.members.filter((m) => m.status === 'approved').length,
      sanctionedEvents: a.sanctionedEvents || 0,
    })),
    ruleBook,
  });
}));

// ==================== @POST /api/associations/:id/register ====================
// "Become a member" - federation membership form submit
// body: { fullName, phone, city, preferredAssociation? }
router.post('/:id/register', protect, wrap('Federation register', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid association id');

  const { fullName, phone, city } = req.body;
  if (!fullName || !String(fullName).trim()) return fail(res, 400, 'Full name is required');
  if (!phone   || !String(phone).trim())    return fail(res, 400, 'Phone number is required');

  const assoc = await Association.findById(req.params.id);
  if (!assoc) return fail(res, 404, 'Association not found.');

  // Already registered?
  const existing = assoc.members.find((m) => String(m.user) === String(req.user._id));
  if (existing) {
    return fail(res, 409, `You have already submitted a registration request (status: ${existing.status}).`);
  }

  assoc.members.push({
    user:     req.user._id,
    fullName: String(fullName).trim(),
    phone:    String(phone).trim(),
    city:     String(city || '').trim(),
    status:   'pending',
  });
  await assoc.save();

  res.status(201).json({
    success: true,
    message: 'Registration submitted! You will receive a Federation ID once approved.',
  });
}));

// ==================== @GET /api/associations/:id/tournaments ====================
// Sanctioned Tournaments list for an association
router.get('/:id/tournaments', protect, wrap('Tournaments', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid id');

  const tournaments = await Tournament.find({ association: req.params.id })
    .sort({ date: 1 });

  res.status(200).json({
    success: true,
    tournaments: tournaments.map((t) => ({
      id:    t._id,
      title: t.title,
      date:  t.date,
      venue: t.venue,
      area:  t.area,
      registrationStatus: t.registrationStatus,
      registeredCount:    t.registeredTeams.length,
    })),
  });
}));

// ==================== @GET /api/associations/tournaments/all ====================
// All sanctioned tournaments (Association tab > Sanctioned Tournaments list)
router.get('/tournaments/all', protect, wrap('All tournaments', async (req, res) => {
  const tournaments = await Tournament.find({})
    .populate('association', 'name city')
    .sort({ date: 1 });

  res.status(200).json({
    success: true,
    tournaments: tournaments.map((t) => ({
      id:    t._id,
      title: t.title,
      date:  t.date,
      venue: t.venue || '',
      area:  t.area  || '',
      association: t.association ? { id: t.association._id, name: t.association.name, city: t.association.city } : null,
      registrationStatus: t.registrationStatus,
      registeredCount:    t.registeredTeams.length,
    })),
  });
}));

// ==================== @POST /api/associations/tournaments/:id/register ====================
// Team tournament ke liye register karti hai
router.post('/tournaments/:id/register', protect, wrap('Tournament register', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid tournament id');

  const me = await User.findById(req.user._id).select('team');
  if (!me.team) return fail(res, 400, 'You must be in a team to register for a tournament.');

  const tournament = await Tournament.findById(req.params.id);
  if (!tournament) return fail(res, 404, 'Tournament not found.');
  if (tournament.registrationStatus === 'closed') return fail(res, 400, 'Registrations are closed.');
  if (tournament.registrationStatus === 'invite_only') return fail(res, 400, 'This tournament is invite-only.');
  if (tournament.registrationStatus === 'waitlist') return fail(res, 200, 'Added to waitlist. No spots available currently.');

  if (tournament.registeredTeams.includes(me.team)) {
    return fail(res, 409, 'Your team is already registered for this tournament.');
  }

  tournament.registeredTeams.push(me.team);
  await tournament.save();

  res.status(200).json({
    success: true,
    message: 'Team registered for the tournament!',
  });
}));

module.exports = router;
