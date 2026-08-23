.pragma library
.import "Model.js" as Model

// QML creates one instance of this library per engine. Every monitor-local
// widget therefore coordinates through these configuration-isolated groups.
var groups = ({})
var nextClaimId = 1

function group(signature) {
  var key = String(signature)
  if (!groups[key]) {
    groups[key] = {
      signature: key,
      members: [],
      fetching: false,
      startedMs: 0,
      publishedMs: 0,
      payload: null,
      claimant: null,
      claimId: 0
    }
  }
  return groups[key]
}

function join(signature, member) {
  var state = group(signature)
  if (state.members.indexOf(member) < 0) state.members.push(member)
  if (state.fetching && member && typeof member.applySharedLoading === "function") member.applySharedLoading()
  return state.payload
}

function leave(signature, member) {
  var state = group(signature)
  var index = state.members.indexOf(member)
  if (index >= 0) state.members.splice(index, 1)
  if (state.claimant === member) state.claimant = null
}

// Manual claims ignore freshness but never race a live claim. An expired claim
// gets a new id, allowing owners that opt into claim ids to reject late output.
function claim(signature, nowMs, forced, freshnessMs, owner) {
  var state = group(signature)
  if (!Model.shouldClaimRefresh(state, nowMs, forced, freshnessMs)) return false
  state.fetching = true
  state.startedMs = Number(nowMs) || 0
  state.claimant = owner || null
  state.claimId = nextClaimId++
  for (var i = 0; i < state.members.length; i++) {
    var member = state.members[i]
    if (!member || member === owner) continue
    if (typeof member.applySharedLoading === "function") member.applySharedLoading()
  }
  return true
}

function currentClaim(signature) {
  var state = group(signature)
  return state.fetching ? state.claimId : 0
}

function abandon(signature, owner, claimId) {
  var state = group(signature)
  if (owner && state.claimant && state.claimant !== owner) return false
  if (claimId && state.claimId !== claimId) return false
  state.fetching = false
  state.startedMs = 0
  state.claimant = null
  for (var i = 0; i < state.members.length; i++) {
    var member = state.members[i]
    if (!member || member === owner) continue
    if (typeof member.applySharedAbandoned === "function") member.applySharedAbandoned()
  }
  return true
}

function publish(signature, payload, nowMs, origin, claimId) {
  var state = group(signature)
  if (claimId && state.claimId !== claimId) return false
  if (state.claimant && origin && state.claimant !== origin) return false
  state.fetching = false
  state.startedMs = 0
  state.claimant = null
  state.payload = payload
  state.publishedMs = Number(nowMs) || 0
  for (var i = 0; i < state.members.length; i++) {
    var member = state.members[i]
    if (!member || member === origin) continue
    if (typeof member.applyShared === "function") member.applyShared(payload)
  }
  return true
}

function snapshot(signature) {
  return group(signature).payload
}

function memberCount(signature) {
  return group(signature).members.length
}

function isClaimed(signature, nowMs) {
  var state = group(signature)
  if (!state.fetching) return false
  return Number(nowMs) - Number(state.startedMs || 0) < Model.CLAIM_TIMEOUT_MS
}

function resetForTests() {
  groups = ({})
  nextClaimId = 1
}
