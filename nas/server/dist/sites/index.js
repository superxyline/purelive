"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerSite = registerSite;
exports.getSite = getSite;
exports.allSites = allSites;
__exportStar(require("./types"), exports);
const registry = new Map();
function registerSite(platform, site) {
    registry.set(platform, site);
}
function getSite(platform) {
    const site = registry.get(platform);
    if (!site)
        throw Object.assign(new Error(`unknown platform: ${platform}`), { statusCode: 404 });
    return site;
}
function allSites() {
    return registry;
}
// 各平台实现（按移植进度逐个启用）
require("./bilibili");
require("./douyu");
require("./huya");
require("./douyin");
require("./kuaishou");
