const express = require('express');
const Team = require('../models/Team');
const User = require('../models/User');
const Battle = require('../models/Battle');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const sid = (v) => String(v && v._id ? v._id : v);

const MIN_LEN = 2;
const PER_SECTION = 5;

// ==================== @GET /api/search?q=kite ====================
// Home screen search bar: matches, venues, teams, players - all in a single call.
// Each section returns at most 5 results. q must be at least 2 letters.
router.get('/', protect, async (req, res) => {
  try {
    const q = String(req.query.q || '').trim().slice(0, 50);
    const empty = { matches: [], venues: [], teams: [], players: [] };

    if (q.length < MIN_LEN) {
      return res.status(200).json({ success: true, query: q, ...empty, total: 0 });
    }

    const re = new RegExp(escapeRe(q), 'i');

    // Teams (public only) - name / tag / region / city
    const teamsP = Team.find({
      isPublic: true,
      $or: [{ name: re }, { tag: re }, { region: re }, { city: re }],
    })
      .select('name tag region city members maxMembers')
      .sort({ createdAt: -1 })
      .limit(PER_SECTION);

    // Players - verified users, not your own name. Email/phone are never sent.
    const playersP = User.find({
      _id: { $ne: req.user._id },
      isVerified: true,
      $or: [{ name: re }, { city: re }],
    })
      .select('name city stats team')
      .populate('team', 'name tag')
      .limit(PER_SECTION);

    // Matches - matched by venue/area or by a team name/tag
    const matchesP = (async () => {
      const teamIds = await Team.find({ $or: [{ name: re }, { tag: re }] })
        .select('_id')
        .limit(30)
        .lean();
      const ids = teamIds.map((t) => t._id);
      const battles = await Battle.find({
        status: { $in: ['live', 'pending', 'accepted', 'final'] },
        $or: [
          { venue: re },
          { area: re },
          { challengerTeam: { $in: ids } },
          { opponentTeam: { $in: ids } },
        ],
      })
        .populate('challengerTeam', 'name tag')
        .populate('opponentTeam', 'name tag')
        .sort({ createdAt: -1 })
        .limit(PER_SECTION);
      return battles;
    })();

    // Venues - unique venues of the battles whose venue/area matched
    const venuesP = Battle.aggregate([
      {
        $match: {
          venue: { $nin: ['', null] },
          $or: [{ venue: re }, { area: re }],
        },
      },
      { $group: { _id: { venue: '$venue', area: '$area' }, matches: { $sum: 1 } } },
      { $sort: { matches: -1 } },
      { $limit: PER_SECTION },
    ]);

    const [teams, players, battles, venues] = await Promise.all([teamsP, playersP, matchesP, venuesP]);

    const out = {
      matches: battles.map((b) => ({
        id: b._id,
        status: b.status,
        venue: b.venue || '',
        area: b.area || '',
        challengerTeam: { id: sid(b.challengerTeam), name: b.challengerTeam?.name || '', tag: b.challengerTeam?.tag || '' },
        opponentTeam: { id: sid(b.opponentTeam), name: b.opponentTeam?.name || '', tag: b.opponentTeam?.tag || '' },
        challengerCuts: b.challengerCuts,
        opponentCuts: b.opponentCuts,
      })),
      venues: venues.map((v) => ({
        venue: v._id.venue,
        area: v._id.area || '',
        matches: v.matches,
      })),
      teams: teams.map((t) => ({
        id: t._id,
        name: t.name,
        tag: t.tag || '',
        region: t.region || t.city || '',
        memberCount: t.members.length,
        maxMembers: t.maxMembers || 10,
      })),
      players: players.map((u) => ({
        id: u._id,
        name: u.name,
        city: u.city || '',
        team: u.team ? { id: u.team._id, name: u.team.name, tag: u.team.tag || '' } : null,
        matches: u.stats?.matches || 0,
        wins: u.stats?.wins || 0,
      })),
    };

    res.status(200).json({
      success: true,
      query: q,
      ...out,
      total: out.matches.length + out.venues.length + out.teams.length + out.players.length,
    });
  } catch (error) {
    console.error('Search error:', error);
    res.status(500).json({ success: false, message: 'Search failed. Try again.' });
  }
});

module.exports = router;
