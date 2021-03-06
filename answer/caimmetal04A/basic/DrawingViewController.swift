//
// DrawingViewController.swift
// CAIM Project
//   http://kengolab.net/CreApp/wiki/
//
// Copyright (c) Watanabe-DENKI Inc.
//   http://wdkk.co.jp/
//
// This software is released under the MIT License.
//   http://opensource.org/licenses/mit-license.php
//

import UIKit

// バッファID番号
let ID_VERTEX:Int     = 0
let ID_PROJECTION:Int = 1

// 頂点情報の構造体
struct VertexInfo {
    var pos:Vec4 = Vec4()
    var uv:Vec2 = Vec2()
    var rgba:CAIMColor = CAIMColor()
}

// パーティクル情報
struct Particle {
    var pos:Vec2 = Vec2()               // xy座標
    var radius:Float = 0.0              // 半径
    var rgba:CAIMColor = CAIMColor()    // パーティクル色
    var life:Float = 0.0                // パーティクルの生存係数(1.0~0.0)
}

// CAIM-Metalを使うビューコントローラ
class DrawingViewController : CAIMMetalViewController
{
    private var pl_circle:CAIMMetalRenderPipeline?      // パーティクル
    
    private var mat:Matrix4x4 = .identity                     // 変換行列
    private var circles = CAIMQuadrangles<VertexInfo>()       // 円用４頂点メッシュ群(はじめは0個)
    // パーティクル情報配列
    private var circle_parts = [Particle]()     // 円用パーティクル情報

    // 円描画シェーダの準備関数
    private func setupCircleEffect() {
        // シェーダを指定してパイプラインの作成
        pl_circle = CAIMMetalRenderPipeline(vertname:"vert2d", fragname:"fragCircleCosCurve")
        pl_circle?.blend_type = .alpha_blend
    }
    
    // パーティクルを生成する関数
    private func genParticle(pos:CGPoint, color:CAIMColor, radius:Float) -> Particle {
        var p:Particle = Particle()
        p.pos = Vec2(Float32(pos.x), Float32(pos.y))
        p.rgba = color
        p.radius = radius
        p.life = 1.0        // ライフを1.0から開始
        return p
    }
    
    // パーティクルのライフの更新
    private func updateLife(in particles:inout [Particle]) {
        // パーティクル情報の更新
        for i:Int in 0 ..< particles.count {
            // パーティクルのライフを減らす(60FPSで1.5秒間保つようにする)
            particles[i].life -= 1.0 / (1.5 * 60.0)
            // ライフが0は下回らないようにする
            particles[i].life = max(0.0, particles[i].life)
        }
    }
    
    // ライフが0のパーティクルを捨てる
    private func trashParticles(in particles:inout [Particle]) {
        // 配列を後ろからスキャンしながら、lifeが0になったものを配列から外していく
        for i:Int in (0 ..< particles.count).reversed() {
            if(particles[i].life <= 0.0) {
                particles.remove(at: i)
            }
        }
    }
    
    // 円のパーティクル情報から頂点メッシュ情報を更新
    private func genCirclesMesh(particles:[Particle]) {
        // パーティクルの数に合わせてメッシュの数をリサイズする
        circles.resize(count: particles.count)
        for i:Int in 0 ..< circles.count {
            // パーティクル情報を展開して、メッシュ情報を作る材料にする
            let p:Particle = particles[i]
            let x:Float = p.pos.x                   // x座標
            let y:Float = p.pos.y                   // y座標
            let r:Float = p.radius * (1.0 - p.life) // 半径(ライフが短いと半径が大きくなるようにする)
            var rgba:CAIMColor = p.rgba             // 色
            rgba.A *= p.life                        // アルファ値の計算(ライフが短いと薄くなるようにする)
            
            // 四角形メッシュi個目の頂点0
            circles[i][0].pos  = Vec4(x-r, y-r, 0, 1)
            circles[i][0].uv   = Vec2(-1.0, -1.0)
            circles[i][0].rgba = rgba
            // 四角形メッシュi個目の頂点1
            circles[i][1].pos  = Vec4(x+r, y-r, 0, 1)
            circles[i][1].uv   = Vec2(1.0, -1.0)
            circles[i][1].rgba = rgba
            // 四角形メッシュi個目の頂点2
            circles[i][2].pos  = Vec4(x-r, y+r, 0, 1)
            circles[i][2].uv   = Vec2(-1.0, 1.0)
            circles[i][2].rgba = rgba
            // 四角形メッシュi個目の頂点3
            circles[i][3].pos  = Vec4(x+r, y+r, 0, 1)
            circles[i][3].uv   = Vec2(1.0, 1.0)
            circles[i][3].rgba = rgba
        }
    }
    
    // 円の描画
    private func drawCircles(renderer:CAIMMetalRenderer) {
        // パイプライン(シェーダ)の切り替え
        renderer.use(pl_circle)
        // CPUの頂点メッシュメモリからGPUバッファを作成し、シェーダ番号をリンクする
        renderer.link(circles.metalBuffer, to:.vertex, at:ID_VERTEX)
        renderer.link(mat.metalBuffer, to:.vertex, at:ID_PROJECTION)
        // GPU描画実行(circlesを渡して4頂点メッシュを描画)
        renderer.draw(circles)
    }
    
    // 準備関数
    override func setup() {
        // ピクセルプロジェクション行列バッファの作成(画面サイズに合わせる)
        mat = Matrix4x4.pixelProjection(CAIMScreenPixel)
        // 円描画シェーダの準備
        setupCircleEffect()
    }
    
    // 繰り返し処理関数
    override func update(renderer:CAIMMetalRenderer) {
        // タッチ位置にパーティクル発生
        for pos:CGPoint in touch_pos {
            // 新しいパーティクルを生成
            let p = genParticle(pos: pos,
                                color: CAIMColor(R: CAIMRandom(), G: CAIMRandom(), B: CAIMRandom(), A: CAIMRandom()),
                                radius: CAIMRandom(120.0) + 60.0)
            // パーティクルを追加
            circle_parts.append(p)
        }
        
        // 円パーティクルのライフの更新
        updateLife(in: &circle_parts)
        // 不要な円パーティクルの削除
        trashParticles(in: &circle_parts)
        
        // パーティクル情報がない場合処理しない
        if(circle_parts.count > 0) {
            // パーティクル情報からメッシュ情報を更新
            genCirclesMesh(particles:circle_parts)
            // 円の描画
            drawCircles(renderer: renderer)
        }
    }
}
