"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.signRoutes = void 0;
const douyu_1 = require("../sign/douyu");
const douyin_1 = require("../sign/douyin");
/** 签名端点：Flutter Web 端无 QuickJS，斗鱼/抖音取流签名在这里执行原 JS 片段。 */
const signRoutes = async (app) => {
    app.post('/douyu', async (req) => {
        return { sign: (0, douyu_1.evalDouyuSign)(req.body.html, req.body.rid) };
    });
    app.post('/douyin/abogus', async (req) => {
        return { result: (0, douyin_1.evalDouyinAbogus)(req.body.url, req.body.userAgent) };
    });
    app.post('/douyin/signature', async (req) => {
        return { result: (0, douyin_1.evalDouyinSignature)(req.body.roomId, req.body.uniqueId) };
    });
    app.post('/douyin/msStub', async (req) => {
        return { result: (0, douyin_1.evalDouyinMsStub)(req.body.roomId, req.body.uniqueId) };
    });
};
exports.signRoutes = signRoutes;
