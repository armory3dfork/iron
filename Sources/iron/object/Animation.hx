package iron.object;

import iron.math.Vec4;
import iron.math.Mat4;
import iron.math.Quat;
import iron.data.MeshData;
import iron.data.SceneFormat;
import iron.data.Armature;

class Animation {

	public var isSkinned:Bool;
	public var isSampled:Bool;
	public var action = '';
	public var armature:Armature; // Bone

	// Lerp
	static var m1 = Mat4.identity();
	static var m2 = Mat4.identity();
	static var vpos = new Vec4();
	static var vpos2 = new Vec4();
	static var vscl = new Vec4();
	static var vscl2 = new Vec4();
	static var q1 = new Quat();
	static var q2 = new Quat();

	public var time = 0.0;
	public var speed = 1.0;
	public var loop = true;
	public var frameIndex = 0; // TODO: use boneTimeIndices
	public var onComplete:Void->Void = null;
	public var paused = false;
	var frameTime:kha.FastFloat;

	var blendTime = 0.0;
	var blendCurrent = 0.0;
	var blendAction = '';

	function new() {
		Scene.active.animations.push(this);
		frameTime = Scene.active.raw.frame_time;
		play();
	}

	public function play(action = '', onComplete:Void->Void = null, blendTime = 0.0, speed = 1.0, loop = true) {
		if (blendTime > 0) {
			this.blendTime = blendTime;
			this.blendCurrent = 0.0;
			this.blendAction = this.action;
		}
		else frameIndex = -1;
		this.action = action;
		this.onComplete = onComplete;
		this.speed = speed;
		this.loop = loop;
		paused = false;
	}

	public function pause() {
		paused = true;
	}

	public function resume() {
		paused = false;
	}

	public function remove() {
		Scene.active.animations.remove(this);
	}

	public function update(delta:Float) {
		if (paused) return;
		time += delta * speed;

		if (blendTime > 0) {
			blendCurrent += delta;
			if (blendCurrent >= blendTime) blendTime = 0.0;
		}
	}

	inline function isTrackEnd(track:TTrack):Bool {
		return speed > 0 ?
			frameIndex >= track.frames.length - 1 :
			frameIndex <= 0;
	}

	inline function checkFrameIndex(frameValues:kha.arrays.Uint32Array):Bool {
		return speed > 0 ?
			((frameIndex + 1) < frameValues.length && time > frameValues[frameIndex + 1] * frameTime) :
			((frameIndex - 1) > -1 && time < frameValues[frameIndex - 1] * frameTime);
	}

	function rewind(track:TTrack) {
		frameIndex = speed > 0 ? 0 : track.frames.length - 1;
		time = track.frames[frameIndex] * frameTime;
	}

	function updateTrack(anim:TAnimation) {
		if (anim == null) return;

		var track = anim.tracks[0];

		if (frameIndex == -1) rewind(track);

		// Move keyframe
		//var frameIndex = boneTimeIndices.get(b);
		var sign = speed > 0 ? 1 : -1;
		while (checkFrameIndex(track.frames)) frameIndex += sign;
		//boneTimeIndices.set(b, frameIndex);

		// Marker events
		if (markerEvents != null && anim.marker_names != null && frameIndex != lastFrameIndex) {
			for (i in 0...anim.marker_frames.length) {
				if (frameIndex == anim.marker_frames[i]) {
					var ar = markerEvents.get(anim.marker_names[i]);
					for (f in ar) f();
				}
			}
			lastFrameIndex = frameIndex;
		}

		// End of track
		if (isTrackEnd(track)) {
			if (loop || blendTime > 0) rewind(track);
			else { frameIndex -= sign; paused = true; }
			if (onComplete != null && blendTime == 0) onComplete();
			//boneTimeIndices.set(b, frameIndex);
		}
	}

	function updateAnimSampled(anim:TAnimation, targetMatrix:Mat4) {
		if (anim == null) return;
		var track = anim.tracks[0];
		var sign = speed > 0 ? 1 : -1;

		var t = time;
		var ti = frameIndex;
		var t1 = track.frames[ti] * frameTime;
		var t2 = track.frames[ti + sign] * frameTime;
		var s = (t - t1) / (t2 - t1); // Linear

		m1.setF32(track.values, ti * 16); // Offset to 4x4 matrix array
		m2.setF32(track.values, (ti + sign) * 16);

		// Decompose
		m1.decompose(vpos, q1, vscl);
		m2.decompose(vpos2, q2, vscl2);

		// Lerp
		var fp = Vec4.lerp(vpos, vpos2, 1.0 - s);
		var fs = Vec4.lerp(vscl, vscl2, 1.0 - s);
		var fq = Quat.lerp(q1, q2, s);

		// Compose
		var m = targetMatrix;
		fq.toMat(m);
		m.scale(fs);
		m._30 = fp.x;
		m._31 = fp.y;
		m._32 = fp.z;
		// boneMats.set(b, m);
	}

	var lastFrameIndex = -1;
	var markerEvents:Map<String, Array<Void->Void>> = null;
	
	public function notifyOnMarker(name:String, onMarker:Void->Void) {
		if (markerEvents == null) markerEvents = new Map();
		var ar = markerEvents.get(name);
		if (ar == null) { ar = []; markerEvents.set(name, ar); }
		ar.push(onMarker);
	}

	public function removeMarker(name:String, onMarker:Void->Void) {
		markerEvents.get(name).remove(onMarker);
	}

	public function currentFrame():Int { return Std.int(time / frameTime); }
	public function totalFrames():Int { return 0; }

	#if arm_debug
	public static var animationTime = 0.0;
	static var startTime = 0.0;
	static function beginProfile() { startTime = kha.Scheduler.realTime(); }
	static function endProfile() { animationTime += kha.Scheduler.realTime() - startTime; }
	public static function endFrame() { animationTime = 0; }
	#end
}
