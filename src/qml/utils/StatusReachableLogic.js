.pragma library
/**
 * StatusReachableLogic.js
 *
 * Lógica para status alcançáveis a partir do status atual (workflow_metadata).
 * Usado pelo componente de status das abas 7 e 8 (work items).
 * Baseado em HappyPathWizard._reachableStatusIds e _canTransitionFromTo.
 */

/**
 * Constrói mapa de adjacências: statusId -> [ toId1, toId2, ... ].
 * Inclui arestas directed e global; initial não gera arco de outro status.
 * @param {Object} workflowEntry - { statuses, transitions }
 * @returns {Object} { adjacency: Object, allStatusIds: string[], initialToId: string }
 */
function buildAdjacency(workflowEntry) {
    var out = { adjacency: {}, allStatusIds: [], initialToId: "" };
    if (!workflowEntry || !workflowEntry.transitions)
        return out;
    var statuses = workflowEntry.statuses || [];
    var statusIds = {};
    for (var s = 0; s < statuses.length; s++) {
        var sid = statuses[s] && (statuses[s].id !== undefined && statuses[s].id !== null) ? String(statuses[s].id) : "";
        if (sid) {
            statusIds[sid] = true;
            out.allStatusIds.push(sid);
        }
    }
    var transitions = workflowEntry.transitions;
    for (var i = 0; i < transitions.length; i++) {
        var t = transitions[i];
        var typ = (t.type || "").toLowerCase();
        var toObj = t.to;
        var toId = toObj && (toObj.id !== undefined && toObj.id !== null) ? String(toObj.id) : "";
        if (!toId)
            continue;
        if (typ === "initial") {
            out.initialToId = toId;
            continue;
        }
        if (typ === "global") {
            for (var k in statusIds) {
                if (!out.adjacency[k])
                    out.adjacency[k] = [];
                if (out.adjacency[k].indexOf(toId) < 0)
                    out.adjacency[k].push(toId);
            }
            continue;
        }
        if (typ === "directed" && t.from && typeof t.from.length === "number") {
            for (var f = 0; f < t.from.length; f++) {
                var fromId = String(t.from[f]);
                if (!out.adjacency[fromId])
                    out.adjacency[fromId] = [];
                if (out.adjacency[fromId].indexOf(toId) < 0)
                    out.adjacency[fromId].push(toId);
            }
        }
    }
    return out;
}

/**
 * Retorna todos os IDs alcançáveis a partir de fromStatusId (fecho transitivo, BFS).
 * Se fromStatusId === "", usa nós de partida = destino(s) da transição initial.
 * @param {Object} workflowEntry - { statuses, transitions }
 * @param {string} fromStatusId - ID do status atual (ou "" se criação)
 * @returns {string[]}
 */
function reachableStatusIdsFull(workflowEntry, fromStatusId) {
    var built = buildAdjacency(workflowEntry);
    var adj = built.adjacency;
    var startIds = [];
    if (fromStatusId && fromStatusId.trim() !== "") {
        startIds.push(String(fromStatusId).trim());
    } else {
        if (built.initialToId)
            startIds.push(built.initialToId);
    }
    var visited = {};
    var queue = startIds.slice();
    for (var q = 0; q < queue.length; q++) {
        var id = queue[q];
        if (visited[id])
            continue;
        visited[id] = true;
        var next = adj[id];
        if (next && typeof next.length === "number") {
            for (var n = 0; n < next.length; n++) {
                var nid = next[n];
                if (!visited[nid])
                    queue.push(nid);
            }
        }
    }
    return Object.keys(visited);
}

/**
 * Retorna IDs de status para os quais existe uma transição a partir de fromStatusId.
 * @param {Object} workflowEntry - { statuses, transitions } do workflow_metadata
 * @param {string} fromStatusId - ID do status atual (ou "" se criação)
 * @returns {string[]} Lista de IDs de status alcançáveis
 */
function reachableStatusIds(workflowEntry, fromStatusId) {
    if (!workflowEntry)
        return [];
    var transitions = workflowEntry.transitions;
    if (!transitions || typeof transitions.length !== "number")
        return [];
    var out = [];
    var seen = {};
    for (var i = 0; i < transitions.length; i++) {
        var t = transitions[i];
        var toObj = t.to;
        var toId = toObj && (toObj.id !== undefined && toObj.id !== null) ? String(toObj.id) : "";
        if (!toId || seen[toId])
            continue;
        var typ = (t.type || "").toLowerCase();
        if (typ === "global") {
            out.push(toId);
            seen[toId] = true;
            continue;
        }
        if (typ === "initial") {
            if (!fromStatusId) {
                out.push(toId);
                seen[toId] = true;
            }
            continue;
        }
        var fromIds = t.from || [];
        if (fromIds && typeof fromIds.length === "number") {
            for (var fi = 0; fi < fromIds.length; fi++) {
                if (String(fromIds[fi]) === String(fromStatusId)) {
                    out.push(toId);
                    seen[toId] = true;
                    break;
                }
            }
        }
    }
    return out;
}

/**
 * Retorna array de status IDs na ordem de exibição: primeiro o destino da transition type "initial",
 * depois os destinos das outras transitions por ordem de aparição, depois os restantes statuses.
 * @param {Object} workflowEntry - { statuses, transitions }
 * @returns {string[]}
 */
function statusDisplayOrder(workflowEntry) {
    if (!workflowEntry || !workflowEntry.transitions || typeof workflowEntry.transitions.length !== "number")
        return [];
    var order = [];
    var seen = {};
    var transitions = workflowEntry.transitions;
    // 1) Primeiro: destino da transition type "initial"
    for (var i = 0; i < transitions.length; i++) {
        var t = transitions[i];
        if ((t.type || "").toLowerCase() !== "initial")
            continue;
        var toObj = t.to;
        var toId = toObj && (toObj.id !== undefined && toObj.id !== null) ? String(toObj.id) : "";
        if (toId && !seen[toId]) {
            order.push(toId);
            seen[toId] = true;
        }
        break;
    }
    // 2) Demais transitions: acrescentar to.id se ainda não está na lista
    for (var j = 0; j < transitions.length; j++) {
        var tr = transitions[j];
        var to = tr.to;
        var id = to && (to.id !== undefined && to.id !== null) ? String(to.id) : "";
        if (id && !seen[id]) {
            order.push(id);
            seen[id] = true;
        }
    }
    // 3) Statuses que não aparecem em nenhum to
    var statuses = workflowEntry.statuses;
    if (statuses && typeof statuses.length === "number") {
        for (var k = 0; k < statuses.length; k++) {
            var st = statuses[k];
            var sid = st && (st.id !== undefined && st.id !== null) ? String(st.id) : "";
            if (sid && !seen[sid]) {
                order.push(sid);
                seen[sid] = true;
            }
        }
    }
    return order;
}

/**
 * Retorna array de status IDs que são destino de alguma transição type "global".
 * @param {Object} workflowEntry - { statuses, transitions }
 * @returns {string[]}
 */
function statusIdsGlobalColumn(workflowEntry) {
    if (!workflowEntry || !workflowEntry.transitions)
        return [];
    var out = [];
    var seen = {};
    for (var i = 0; i < workflowEntry.transitions.length; i++) {
        var t = workflowEntry.transitions[i];
        if ((t.type || "").toLowerCase() !== "global")
            continue;
        var toId = t.to && (t.to.id !== undefined && t.to.id !== null) ? String(t.to.id) : "";
        if (toId && !seen[toId]) {
            out.push(toId);
            seen[toId] = true;
        }
    }
    return out;
}

/**
 * Adjacência apenas com arestas directed (para path-finding e ordem main column).
 * @param {Object} workflowEntry - { statuses, transitions }
 * @returns {Object} { adjacency: Object, initialToId: string }
 */
function buildDirectedOnlyAdjacency(workflowEntry) {
    var out = { adjacency: {}, initialToId: "" };
    if (!workflowEntry || !workflowEntry.transitions)
        return out;
    var transitions = workflowEntry.transitions;
    for (var i = 0; i < transitions.length; i++) {
        var t = transitions[i];
        var typ = (t.type || "").toLowerCase();
        var toObj = t.to;
        var toId = toObj && (toObj.id !== undefined && toObj.id !== null) ? String(toObj.id) : "";
        if (!toId)
            continue;
        if (typ === "initial") {
            out.initialToId = toId;
            continue;
        }
        if (typ === "directed" && t.from && typeof t.from.length === "number") {
            for (var f = 0; f < t.from.length; f++) {
                var fromId = String(t.from[f]);
                if (!out.adjacency[fromId])
                    out.adjacency[fromId] = [];
                if (out.adjacency[fromId].indexOf(toId) < 0)
                    out.adjacency[fromId].push(toId);
            }
        }
    }
    return out;
}

/**
 * Status é "done positivo" se category === "done" e nome normalizado é "done" (ou único done no workflow).
 * "Done negativo" = category "done" e não positivo (ex.: Canceled, Won't Do).
 */
function _isDonePositive(statusObj) {
    if (!statusObj)
        return false;
    var cat = (statusObj.category || "").toLowerCase();
    var name = (statusObj.name || "").toString().trim().toLowerCase();
    if (cat !== "done")
        return false;
    return name === "done";
}

function _getStatusById(workflowEntry, statusId) {
    if (!workflowEntry || !workflowEntry.statuses)
        return null;
    var id = String(statusId);
    for (var i = 0; i < workflowEntry.statuses.length; i++) {
        if (String(workflowEntry.statuses[i].id) === id)
            return workflowEntry.statuses[i];
    }
    return null;
}

/**
 * Ordem da coluna principal: initial, depois caminho mais curto (só directed) até primeiro done positivo,
 * depois done negativos (outros category done). Exclui IDs que estão só em statusIdsGlobalColumn.
 * @param {Object} workflowEntry - { statuses, transitions }
 * @returns {string[]}
 */
function statusDisplayOrderMainColumn(workflowEntry) {
    if (!workflowEntry || !workflowEntry.statuses)
        return [];
    var directed = buildDirectedOnlyAdjacency(workflowEntry);
    var globalIds = {};
    var gcol = statusIdsGlobalColumn(workflowEntry);
    for (var gi = 0; gi < gcol.length; gi++)
        globalIds[gcol[gi]] = true;
    var initialId = directed.initialToId;
    if (!initialId)
        return statusDisplayOrder(workflowEntry);
    var adj = directed.adjacency;
    var pathToFirstDone = [];
    var queue = [[initialId]];
    var visited = {};
    while (queue.length > 0) {
        var path = queue.shift();
        var node = path[path.length - 1];
        if (visited[node])
            continue;
        visited[node] = true;
        var stObj = _getStatusById(workflowEntry, node);
        if (stObj && _isDonePositive(stObj)) {
            pathToFirstDone = path;
            break;
        }
        var nextList = adj[node];
        if (nextList && nextList.length > 0) {
            for (var n = 0; n < nextList.length; n++) {
                var nid = nextList[n];
                if (!visited[nid])
                    queue.push(path.concat([nid]));
            }
        }
    }
    var order = [];
    for (var p = 0; p < pathToFirstDone.length; p++) {
        if (!globalIds[pathToFirstDone[p]])
            order.push(pathToFirstDone[p]);
    }
    var statuses = workflowEntry.statuses;
    for (var s = 0; s < statuses.length; s++) {
        var st = statuses[s];
        var sid = st && (st.id !== undefined && st.id !== null) ? String(st.id) : "";
        if (!sid || globalIds[sid])
            continue;
        var cat = (st.category || "").toLowerCase();
        if (cat === "done" && !_isDonePositive(st)) {
            if (order.indexOf(sid) < 0)
                order.push(sid);
        }
    }
    var seenOrder = {};
    for (var o = 0; o < order.length; o++)
        seenOrder[order[o]] = true;
    for (var s2 = 0; s2 < statuses.length; s2++) {
        var sid2 = statuses[s2] && (statuses[s2].id !== undefined && statuses[s2].id !== null) ? String(statuses[s2].id) : "";
        if (sid2 && !seenOrder[sid2] && !globalIds[sid2])
            order.push(sid2);
    }
    return order;
}

/**
 * Encontra todos os caminhos de fromStatusId a toStatusId (máx. 20 caminhos, depth máx. 10).
 * Caminho = array de status IDs [from, ..., to].
 * Regras: (1) target = initial -> []; (2) existe global para target -> [[from, to]]; (3) senão subgrafo só directed.
 * @param {Object} workflowEntry - { statuses, transitions }
 * @param {string} fromStatusId - ID status atual
 * @param {string} toStatusId - ID status alvo
 * @returns {Array<Array<string>>} Lista de caminhos (cada caminho é array de IDs)
 */
function findPaths(workflowEntry, fromStatusId, toStatusId) {
    if (!workflowEntry || !fromStatusId || !toStatusId)
        return [];
    var fromId = String(fromStatusId).trim();
    var toId = String(toStatusId).trim();
    if (fromId === toId)
        return [];
    var built = buildDirectedOnlyAdjacency(workflowEntry);
    var initialToId = built.initialToId;
    if (toId === initialToId)
        return [];
    var transitions = workflowEntry.transitions || [];
    for (var ti = 0; ti < transitions.length; ti++) {
        if ((transitions[ti].type || "").toLowerCase() !== "global")
            continue;
        var gTo = transitions[ti].to;
        var gToId = gTo && (gTo.id !== undefined && gTo.id !== null) ? String(gTo.id) : "";
        if (gToId === toId)
            return [[fromId, toId]];
    }
    var adj = built.adjacency;
    var paths = [];
    var maxPaths = 20;
    var maxDepth = 10;
    function dfs(path, depth) {
        if (paths.length >= maxPaths || depth > maxDepth)
            return;
        var node = path[path.length - 1];
        if (node === toId) {
            paths.push(path.slice());
            return;
        }
        var nextList = adj[node];
        if (!nextList || nextList.length === 0)
            return;
        for (var i = 0; i < nextList.length; i++) {
            var nid = nextList[i];
            if (path.indexOf(nid) >= 0)
                continue;
            path.push(nid);
            dfs(path, depth + 1);
            path.pop();
        }
    }
    dfs([fromId], 0);
    return paths;
}

/**
 * Constrói opções separadas por coluna: main (ordem directed + done) e global.
 * @param {Object} workflowEntry - { statuses, transitions }
 * @param {string} currentStatusNameOrId - Nome ou ID do status atual (ou "" em criação)
 * @param {boolean} allEnabled - Se true (criação), todos enabled; senão usa reachable full.
 * @returns {{ mainColumn: Array<{id, name, enabled}>, globalColumn: Array<{id, name, enabled}> }}
 */
function buildStatusOptionsWithColumns(workflowEntry, currentStatusNameOrId, allEnabled) {
    var mainColumn = [];
    var globalColumn = [];
    if (!workflowEntry || !workflowEntry.statuses)
        return { mainColumn: mainColumn, globalColumn: globalColumn };
    var statuses = workflowEntry.statuses;
    var idToName = {};
    for (var s = 0; s < statuses.length; s++) {
        var st = statuses[s];
        var id = st && (st.id !== undefined && st.id !== null) ? String(st.id) : "";
        var name = (st && st.name) ? String(st.name) : id;
        if (id)
            idToName[id] = name;
    }
    var currentId = "";
    if (currentStatusNameOrId) {
        var nameToId = {};
        for (var k in idToName)
            nameToId[idToName[k]] = k;
        nameToId[""] = "";
        currentId = nameToId[currentStatusNameOrId] || nameToId[String(currentStatusNameOrId).toUpperCase()] || "";
        if (!currentId && String(currentStatusNameOrId).match(/^\d+$/))
            currentId = String(currentStatusNameOrId);
    }
    var reachableSet = {};
    var initialToId = "";
    if (!allEnabled) {
        var directed = buildDirectedOnlyAdjacency(workflowEntry);
        initialToId = directed.initialToId || "";
        var reachableIds = reachableStatusIdsFull(workflowEntry, currentId);
        for (var r = 0; r < reachableIds.length; r++)
            reachableSet[reachableIds[r]] = true;
    }
    var mainOrder = statusDisplayOrderMainColumn(workflowEntry);
    var globalOrder = statusIdsGlobalColumn(workflowEntry);
    for (var i = 0; i < mainOrder.length; i++) {
        var oid = mainOrder[i];
        var enabled = allEnabled || oid === currentId || !!reachableSet[oid];
        if (!allEnabled && initialToId && oid === initialToId && currentId !== initialToId)
            enabled = false;
        mainColumn.push({ id: oid, name: idToName[oid] || oid, enabled: enabled });
    }
    for (var j = 0; j < globalOrder.length; j++) {
        var gid = globalOrder[j];
        var enabledG = allEnabled || gid === currentId || !!reachableSet[gid];
        if (!allEnabled && initialToId && gid === initialToId && currentId !== initialToId)
            enabledG = false;
        globalColumn.push({ id: gid, name: idToName[gid] || gid, enabled: enabledG });
    }
    return { mainColumn: mainColumn, globalColumn: globalColumn };
}

/**
 * Dado workflow entry e status atual (nome ou id), retorna lista de opções:
 * cada item { id, name, enabled } onde enabled = true se é o status atual ou está em reachable.
 * Ordem de exibição dada por statusDisplayOrder (initial primeiro).
 * @param {Object} workflowEntry - { statuses, transitions }
 * @param {string} currentStatusNameOrId - Nome ou ID do status atual
 * @returns {Array<{id: string, name: string, enabled: boolean}>}
 */
function buildStatusOptions(workflowEntry, currentStatusNameOrId) {
    if (!workflowEntry || !workflowEntry.statuses)
        return [];
    var statuses = workflowEntry.statuses;
    if (typeof statuses.length !== "number" || statuses.length === 0)
        return [];
    var idToName = {};
    var nameToId = {};
    for (var s = 0; s < statuses.length; s++) {
        var st = statuses[s];
        var id = st && (st.id !== undefined && st.id !== null) ? String(st.id) : "";
        var name = (st && st.name) ? String(st.name) : id;
        if (id) {
            idToName[id] = name;
            nameToId[name] = id;
            nameToId[name.toUpperCase()] = id;
        }
    }
    var currentId = "";
    if (currentStatusNameOrId) {
        currentId = nameToId[currentStatusNameOrId] || nameToId[String(currentStatusNameOrId).toUpperCase()] || "";
        if (!currentId && String(currentStatusNameOrId).match(/^\d+$/))
            currentId = String(currentStatusNameOrId);
    }
    var reachableIds = reachableStatusIdsFull(workflowEntry, currentId);
    var reachableSet = {};
    for (var r = 0; r < reachableIds.length; r++)
        reachableSet[reachableIds[r]] = true;
    var directed = buildDirectedOnlyAdjacency(workflowEntry);
    var initialToId = directed.initialToId || "";
    var order = statusDisplayOrder(workflowEntry);
    var options = [];
    if (order.length > 0) {
        for (var i = 0; i < order.length; i++) {
            var oid = order[i];
            var name = idToName[oid] || oid;
            var enabled = oid === currentId || !!reachableSet[oid];
            if (initialToId && oid === initialToId && currentId !== initialToId)
                enabled = false;
            options.push({ id: oid, name: name, enabled: enabled });
        }
    } else {
        for (var idx = 0; idx < statuses.length; idx++) {
            var st2 = statuses[idx];
            var id2 = st2 && (st2.id !== undefined && st2.id !== null) ? String(st2.id) : "";
            var name2 = (st2 && st2.name) ? String(st2.name) : id2;
            var enabled2 = id2 === currentId || !!reachableSet[id2];
            if (initialToId && id2 === initialToId && currentId !== initialToId)
                enabled2 = false;
            options.push({ id: id2, name: name2, enabled: enabled2 });
        }
    }
    return options;
}

/**
 * Constrói opções de status com todos habilitados (modo criação: todos os caminhos possíveis).
 * Ordem por statusDisplayOrder. Retorna [{ id, name, enabled: true }] para todos.
 * @param {Object} workflowEntry - { statuses, transitions }
 * @returns {Array<{id: string, name: string, enabled: boolean}>}
 */
function buildStatusOptionsAllEnabled(workflowEntry) {
    if (!workflowEntry || !workflowEntry.statuses)
        return [];
    var statuses = workflowEntry.statuses;
    if (typeof statuses.length !== "number" || statuses.length === 0)
        return [];
    var idToName = {};
    for (var s = 0; s < statuses.length; s++) {
        var st = statuses[s];
        var id = st && (st.id !== undefined && st.id !== null) ? String(st.id) : "";
        var name = (st && st.name) ? String(st.name) : id;
        if (id)
            idToName[id] = name;
    }
    var order = statusDisplayOrder(workflowEntry);
    var options = [];
    if (order.length > 0) {
        for (var i = 0; i < order.length; i++) {
            var oid = order[i];
            options.push({ id: oid, name: idToName[oid] || oid, enabled: true });
        }
    } else {
        for (var idx = 0; idx < statuses.length; idx++) {
            var st2 = statuses[idx];
            var id2 = st2 && (st2.id !== undefined && st2.id !== null) ? String(st2.id) : "";
            var name2 = (st2 && st2.name) ? String(st2.name) : id2;
            options.push({ id: id2, name: name2, enabled: true });
        }
    }
    return options;
}

/**
 * Constrói opções de status com ordem por statusDisplayOrder e enabled a partir da lista
 * de transições disponíveis da API (GET issue/transitions). Habilitados: status atual +
 * todos os destinos (to.id / to.name) das transições em availableTransitions.
 * @param {Object} workflowEntry - { statuses, transitions }
 * @param {string} currentStatusNameOrId - Nome ou ID do status atual
 * @param {Array} availableTransitions - Lista da API: [{ id, name, to: { id, name } }]
 * @returns {Array<{id: string, name: string, enabled: boolean}>}
 */
function buildStatusOptionsFromApi(workflowEntry, currentStatusNameOrId, availableTransitions) {
    if (!workflowEntry || !workflowEntry.statuses)
        return [];
    var statuses = workflowEntry.statuses;
    if (typeof statuses.length !== "number" || statuses.length === 0)
        return [];
    var idToName = {};
    var nameToId = {};
    for (var s = 0; s < statuses.length; s++) {
        var st = statuses[s];
        var id = st && (st.id !== undefined && st.id !== null) ? String(st.id) : "";
        var name = (st && st.name) ? String(st.name) : id;
        if (id) {
            idToName[id] = name;
            nameToId[name] = id;
            nameToId[name.toUpperCase()] = id;
        }
    }
    var currentId = "";
    if (currentStatusNameOrId) {
        currentId = nameToId[currentStatusNameOrId] || nameToId[String(currentStatusNameOrId).toUpperCase()] || "";
        if (!currentId && String(currentStatusNameOrId).match(/^\d+$/))
            currentId = String(currentStatusNameOrId);
    }
    var enabledIds = {};
    enabledIds[currentId] = true;
    var trans = availableTransitions;
    if (trans && typeof trans.length === "number") {
        for (var t = 0; t < trans.length; t++) {
            var toObj = trans[t].to;
            if (toObj) {
                var toId = toObj.id !== undefined && toObj.id !== null ? String(toObj.id) : "";
                var toName = (toObj.name || "").toString();
                if (toId) enabledIds[toId] = true;
                if (toName) {
                    var resolved = nameToId[toName] || nameToId[toName.toUpperCase()];
                    if (resolved) enabledIds[resolved] = true;
                }
            }
        }
    }
    var order = statusDisplayOrder(workflowEntry);
    var options = [];
    if (order.length > 0) {
        for (var i = 0; i < order.length; i++) {
            var oid = order[i];
            var name = idToName[oid] || oid;
            options.push({ id: oid, name: name, enabled: !!enabledIds[oid] });
        }
    } else {
        for (var idx = 0; idx < statuses.length; idx++) {
            var st2 = statuses[idx];
            var id2 = st2 && (st2.id !== undefined && st2.id !== null) ? String(st2.id) : "";
            var name2 = (st2 && st2.name) ? String(st2.name) : id2;
            options.push({ id: id2, name: name2, enabled: !!enabledIds[id2] });
        }
    }
    return options;
}
