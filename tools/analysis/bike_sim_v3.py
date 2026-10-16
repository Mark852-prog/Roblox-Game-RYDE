"""
Offline model of the PLANNED BikePhysics v3 force laws (pitch plane), used to
choose numbers before they go into src/shared/Vehicle/BikePhysics.luau.
NOT a Roblox playtest - PhysicsLab measures the real thing.

Changes vs v0.2 (see docs/QUALITY_AUDIT.md section 3.2):
  PH1 suspension force along the ground normal
  PH2 damper from hub velocity along the suspension axis
  PH3 progressive spring in the last part of travel + softer bump stop
  PH4 wheelie control (throttle trimming + rear-brake dab), levels Off/Light/Standard

  python3 tools/analysis/bike_sim_v3.py
"""

import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = json.load(open(os.path.join(HERE, "voltra_spec.json")))
PHYS_HZ = 240
M_PER_STUD = 0.28

# Voltra Storm motor/brake config (src/shared/Config/Vehicles/VoltraStorm.luau)
MOTOR = {"maxDriveForceN": 900, "peakPowerW": 6000, "topSpeedKmh": 75, "rise": 0.25, "fall": 0.15}
BRAKES = {"front": 1300, "rear": 600, "normalFrontShare": 0.25}
MASS_KG = SPEC["totalMassKg"]

# ---- tunables (the values chosen here go into the Luau code) ----
PARAMS = {
    "damping_scale": 1.3,  # multiplies config damping ratios (0.5/0.55 -> 0.65/0.72)
    "progressive_start": 0.6,  # fraction of travel where the spring starts stiffening
    "progressive_gain": 3.0,  # extra stiffness at full travel = gain x k
    "bumpstop_k": 6.0,  # beyond full travel, x k
    "damper_knee": 4.0,  # studs/s (~1.1 m/s): above this, damping is digressive
    "damper_high_ratio": 0.35,  # slope above the knee, as a fraction of normal damping
    "normal_front_share": 0.6,  # front share of the S brake
    "rlp_load": 0.08,  # rear-lift protection: ease the front brake below this rear load (x weight)
    "hbc_start": 0.75,  # hydraulic bottoming control: extra damping beyond this fraction of travel
    "hbc_gain": 0.0,  # extra damping multiplier at full travel
    "predict": 1.0,
    "predict_min_rate": float("inf"),  # prediction only on the touchdown frame (wider use breaks wheelies)
}

WHEELIE = {
    # Electronic wheelie control: PD on pitch -> instant motor trim (u > 0) or rear-brake dab (u < 0)
    "Off": None,
    "Light": {"target": 34, "kp": 0.12, "kd": 0.05, "brake_gain": 1.0},
    "Standard": {"target": 30, "kp": 0.24, "kd": 0.08, "brake_gain": 1.5},
}


def motor_accel(v_studs, throttle):
    if throttle <= 0:
        return 0.0
    mps = max(abs(v_studs) * M_PER_STUD, 0.5)
    force = min(MOTOR["maxDriveForceN"], MOTOR["peakPowerW"] / mps)
    top = MOTOR["topSpeedKmh"] / 3.6 / M_PER_STUD
    fade = top * 0.92
    if v_studs > fade:
        force *= max(0.0, min(1.0, (top - v_studs) / (top - fade)))
    return force * throttle / MASS_KG / M_PER_STUD


def drag_accel(v):
    mps = v * M_PER_STUD
    return 0.5 * 1.225 * 0.6 * mps * mps / MASS_KG / M_PER_STUD


def brake_accel(newtons):
    return newtons / MASS_KG / M_PER_STUD


class Wheel:
    def __init__(self, s, z):
        self.r, self.travel = s["radius"], s["travel"]
        self.omega_sq, self.zeta = s["omegaSq"], s["dampingRatio"] * PARAMS["damping_scale"]
        self.share, self.mount_y, self.z = s["loadShare"], s["mountY"], z
        self.grounded = False


def probe(wheel, cx, cy, th, extra=0.0):
    fx, fy = math.cos(th), math.sin(th)
    ux, uy = -math.sin(th), math.cos(th)
    mx = cx + fx * wheel.z + ux * wheel.mount_y
    my = cy + fy * wheel.z + uy * wheel.mount_y
    oy = my + uy * wheel.r
    if uy <= 1e-3:
        return None
    d = (oy - wheel.r) / uy
    if d < 0 or d > wheel.r + wheel.travel + extra:
        return None
    hub_drop = d - wheel.r
    comp = min(wheel.travel - hub_drop, wheel.travel)  # negative = gap before touching
    return comp, max(-hub_drop, 0.0), mx + ux * (wheel.r - d), (mx, my)


def spring_force(wheel, comp, bottomed, rate, corner):
    k = corner * wheel.omega_sq
    c = 2 * wheel.zeta * corner * math.sqrt(wheel.omega_sq)
    frac = comp / wheel.travel
    extra = 0.0
    if frac > PARAMS["progressive_start"]:
        u = (frac - PARAMS["progressive_start"]) / (1 - PARAMS["progressive_start"])
        extra = k * PARAMS["progressive_gain"] * u * u * (comp - PARAMS["progressive_start"] * wheel.travel) / 3
    knee = PARAMS["damper_knee"]
    if abs(rate) > knee:
        damp = c * math.copysign(knee + (abs(rate) - knee) * PARAMS["damper_high_ratio"], rate)
    else:
        damp = c * rate
    if frac > PARAMS["hbc_start"] and rate > 0:
        damp *= 1 + PARAMS["hbc_gain"] * (frac - PARAMS["hbc_start"]) / (1 - PARAMS["hbc_start"])
    f = k * comp + extra + damp
    if bottomed > 0:
        f += k * PARAMS["bumpstop_k"] * bottomed + c * max(rate, 0)
    return max(f, 0.0)


def simulate(fps, setup, controls, duration, assist="Off"):
    """controls(t, state) -> dict(throttle, brake, frontBrake, lean)."""
    front = Wheel(SPEC["front"], -SPEC["front"]["hubRestZ"])
    rear = Wheel(SPEC["rear"], -SPEC["rear"]["hubRestZ"])
    box = SPEC["box"]
    m = 1.0
    inertia = m * (box[1] ** 2 + box[2] ** 2) / 12
    g = SPEC["gravity"]
    h = SPEC["comHeight"]
    st = {"x": 0.0, "y": h, "th": 0.0, "vx": 0.0, "vy": 0.0, "w": 0.0, "t": 0.0, "throttle": 0.0}
    setup(st)
    dt_frame, sub, dt = 1.0 / fps, PHYS_HZ // fps, 1.0 / PHYS_HZ
    log = {"t": [], "y": [], "th": [], "vx": [], "x": [], "load": [], "min_box": 1e9, "front_up": [], "max_load": 0.0}
    while st["t"] < duration:
        c = controls(st["t"], st)
        throttle_in, brake, front_brake, lean = c.get("throttle", 0), c.get("brake", 0), c.get("frontBrake", 0), c.get("lean", 0)
        th, vx, vy, w = st["th"], st["vx"], st["vy"], st["w"]
        fx, fy = math.cos(th), math.sin(th)
        ux, uy = -math.sin(th), math.cos(th)
        hits = {}
        look = max(0.0, -vy) * dt_frame * 1.5  # also find ground we will reach during this frame

        def touching(hit):
            return hit is not None and hit[0] >= 0

        for wheel in (front, rear):
            hits[id(wheel)] = probe(wheel, st["x"], st["y"], th, look)
        front_up = not touching(hits[id(front)]) and touching(hits[id(rear)])
        # ---- wheelie control (PH4) ----
        rear_brake_extra = 0.0
        cfg = WHEELIE.get(assist)
        rise, fall = 1 / MOTOR["rise"], 1 / MOTOR["fall"]
        step = (rise if throttle_in > st["throttle"] else fall) * dt_frame
        st["throttle"] += max(-step, min(step, throttle_in - st["throttle"]))
        trim = 1.0
        if cfg and front_up and math.degrees(th) > 3 and brake < 0.1:
            u = cfg["kp"] * (cfg["target"] - math.degrees(th)) - cfg["kd"] * math.degrees(w)
            if u >= 0:
                trim = min(1.0, 0.35 + u)
            else:
                trim = max(0.0, 0.35 + u)
                if trim <= 0:
                    rear_brake_extra = min(1.0, -(0.35 + u) * cfg["brake_gain"])
        st["trim"] = trim
        drive = motor_accel(vx, st["throttle"]) * trim
        # Rear-lift protection (normal brake only): ease the front when the rear unloads.
        share = PARAMS["normal_front_share"]
        rl = st.get("rear_load", 1.0)
        if rl < PARAMS["rlp_load"]:
            share *= max(0.3, rl / PARAMS["rlp_load"])
        fb = brake_accel(BRAKES["front"] * max(brake * share, front_brake))
        rb = brake_accel(BRAKES["rear"] * min(1.0, brake + rear_brake_extra))
        Fx = Fy = tau = 0.0
        total_load = 0.0
        for wheel in (front, rear):
            hit = hits[id(wheel)]
            if hit is None:
                wheel.grounded = False
                continue
            comp, bottomed, contact_x, (mx, my) = hit
            corner = m * wheel.share
            # PH2: hub velocity along the suspension axis
            px, py = mx - st["x"], my - st["y"]
            pvx, pvy = vx - w * py, vy + w * px
            rate = -(pvx * ux + pvy * uy)
            # Prediction: where will the suspension be during the coming frame?
            # Only anticipate compression (impacts); an extending suspension keeps
            # its current compression so the tyre doesn't "predict" itself off the ground.
            landing = not wheel.grounded  # touching down this frame
            impact = rate if (landing and rate > 0) else max(rate - PARAMS["predict_min_rate"], 0.0)
            pred = comp + impact * dt_frame * PARAMS["predict"]
            if pred <= 0:
                wheel.grounded = False
                continue  # not touching, and won't be this frame
            bott = bottomed + max(0.0, pred - wheel.travel)
            pred = min(max(pred, 0.0), wheel.travel)
            susp = min(spring_force(wheel, pred, bott, rate, corner), m * g * 12)
            total_load += susp
            if wheel is rear:
                st["_rear_force"] = susp
            long = 0.0
            if wheel is rear:
                long += m * drive
            resist = m * (fb if wheel is front else rb) + 0.015 * susp
            long -= math.copysign(min(resist, abs(vx) * corner / dt_frame), vx) if abs(vx) > 1e-6 else 0.0
            long = max(-susp, min(susp, long))  # mu = 1
            # PH1: along the ground normal (flat ground -> vertical)
            fxw, fyw = long, susp
            Fx += fxw
            Fy += fyw
            rx, ry = contact_x - st["x"], -st["y"]
            tau += rx * fyw - ry * fxw
            wheel.grounded = True
        airborne = not any(touching(hits[id(wh)]) for wh in (front, rear))
        if airborne:
            tau += lean * inertia * 7 * 0.6 - inertia * 0.6 * w
        else:
            tau += lean * m * SPEC["riderFraction"] * g * SPEC["riderShift"]
            if cfg and front_up:
                # Rider body control: resist pitching speed, capped at what a rider's
                # weight shift could produce (so it can't do the impossible).
                cap = m * SPEC["riderFraction"] * g * SPEC["riderShift"] * cfg.get("body_cap", 1.0)
                tau += max(-cap, min(cap, -inertia * cfg.get("body_damp", 0.0) * w))
        Fx -= math.copysign(drag_accel(abs(vx)) * m, vx) if abs(vx) > 0.5 else 0.0
        log["max_load"] = max(log["max_load"], total_load / (m * g))
        rh = hits[id(rear)]
        st["rear_load"] = 0.0 if not touching(rh) else st.get("_rear_force", 0.0) / (m * g)
        for _ in range(sub):
            st["vx"] += Fx / m * dt
            st["vy"] += (Fy / m - g) * dt
            st["w"] += tau / inertia * dt
            st["x"] += st["vx"] * dt
            st["y"] += st["vy"] * dt
            st["th"] += st["w"] * dt
            bottom = st["y"] - box[1] / 2 * math.cos(st["th"]) - abs(box[2] / 2 * math.sin(st["th"]))
            log["min_box"] = min(log["min_box"], bottom)
            if bottom < 0:
                st["y"] -= bottom
                st["vy"] = max(st["vy"], 0)
                st["w"] *= 0.5
            st["t"] += dt
        for key in ("t", "y", "th", "vx", "x"):
            log[key].append(st[key])
        log["load"].append(total_load / (m * g))
        log["front_up"].append(front_up)
        log.setdefault("rear_up", []).append(not touching(hits[id(rear)]) and touching(hits[id(front)]))
    return log


def bounces(series, centre, tol=0.02):
    n, last = 0, 0
    for v in series:
        s = 1 if v > centre + tol else (-1 if v < centre - tol else 0)
        if s and s != last:
            n += 1
            last = s
    return max(0, n - 1) // 2


def kmh(v):
    return v * M_PER_STUD * 3.6


def wheelie_score(assist, fps=60):
    log = simulate(fps, lambda s: s.update(vx=15 / 3.6 / M_PER_STUD), lambda t, s: {"throttle": 1, "lean": 1}, 6, assist)
    ths = [math.degrees(x) for x in log["th"]]
    frame = 6 / len(ths)
    window = sum(1 for a in ths if 15 <= a <= 45) * frame
    return window, max(ths), log


def main():
    out = []
    p = out.append
    p("BikePhysics v3 (planned) - offline model, NOT a Roblox playtest")
    p(f"params: {PARAMS}\n")

    p("Settle (dropped 0.5 studs = 14 cm)           target: <= 2 bounces")
    for fps in (60, 30, 20):
        log = simulate(fps, lambda s: s.update(y=SPEC["comHeight"] + 0.5), lambda t, s: {}, 3)
        p(f"  {fps} fps: bounces {bounces(log['y'], log['y'][-1])}, peak load {log['max_load']:.2f} g")

    p("\nDrop 1.5 m onto flat                         target: box never touches; <= 10 g (>= ~7 g unavoidable with 20 cm travel)")
    for fps in (60, 30, 20):
        log = simulate(fps, lambda s: s.update(y=SPEC["comHeight"] + 1.5 / M_PER_STUD, vx=10), lambda t, s: {}, 3)
        p(f"  {fps} fps: peak load {log['max_load']:.2f} g, min box clearance {log['min_box']:.2f} studs")

    p("\nAcceleration 0-50 km/h and braking 50-0 (S)  target: 3.0-4.0 s; 12-16 m, rear stays down")
    for fps in (60, 30):
        log = simulate(fps, lambda s: None, lambda t, s: {"throttle": 1, "lean": -1 if t < 1.5 else 0}, 8)
        t50 = next((t for t, v in zip(log["t"], log["vx"]) if kmh(v) >= 50), None)
        v50 = 50 / 3.6 / M_PER_STUD
        blog = simulate(fps, lambda s: s.update(vx=v50), lambda t, s: {"brake": 1}, 5)
        stop_i = next((i for i, v in enumerate(blog["vx"]) if v <= 0.05), len(blog["vx"]) - 1)
        dist = (blog["x"][stop_i] - blog["x"][0]) * M_PER_STUD
        rear_lift = sum(blog["rear_up"][:stop_i + 1]) / fps
        p(f"  {fps} fps: 0-50 {t50:.2f} s | stop distance {dist:.1f} m, min pitch {math.degrees(min(blog['th'])):.1f} deg, rear wheel off the ground {rear_lift:.2f} s")

    p("\nWheelie hold: player holds W + Shift for 6 s from 15 km/h    target (Standard): never loops; >= 5 s in 15-45 deg at 60 fps")
    for assist in ("Off", "Light", "Standard"):
        for fps in (60, 30):
            log = simulate(fps, lambda s: s.update(vx=15 / 3.6 / M_PER_STUD), lambda t, s: {"throttle": 1, "lean": 1}, 6, assist)
            ths = [math.degrees(x) for x in log["th"]]
            frame = 6 / len(ths)
            in_window = sum(1 for a, up in zip(ths, log["front_up"]) if 15 <= a <= 45) * frame
            looped = max(ths) > 80
            p(f"  {assist:<8} {fps} fps: time in 15-45 deg {in_window:.1f} s, max pitch {max(ths):6.1f}, looped {looped}, end speed {kmh(log['vx'][-1]):.0f} km/h")

    p("\nWheelie robustness (Standard): entry speed / pulsed throttle (W tapped 0.3 s on, 0.15 s off)")
    for v0 in (5, 15, 25):
        for pulsed in (False, True):
            ctrl = (lambda t, s: {"throttle": 1 if (t % 0.45) < 0.3 else 0, "lean": 1}) if pulsed else (lambda t, s: {"throttle": 1, "lean": 1})
            log = simulate(60, lambda s, v0=v0: s.update(vx=v0 / 3.6 / M_PER_STUD), ctrl, 6, "Standard")
            ths = [math.degrees(x) for x in log["th"]]
            frame = 6 / len(ths)
            p(f"  {v0:>2} km/h {'pulsed' if pulsed else 'held  '}: time in 15-45 deg {sum(1 for a in ths if 15 <= a <= 45) * frame:.1f} s, max {max(ths):.1f}, looped {max(ths) > 80}")

    p("\nWheelie tap: W + Shift 0.4 s then release (Standard)")
    log = simulate(60, lambda s: s.update(vx=15 / 3.6 / M_PER_STUD), lambda t, s: {"throttle": 1, "lean": 1} if t < 0.4 else {}, 4, "Standard")
    ths = [math.degrees(x) for x in log["th"]]
    p(f"  peak {max(ths):.1f} deg, end {ths[-1]:.1f} deg")

    p("\nWheelie dropped with rear brake: hold to 3 s, then S")
    log = simulate(60, lambda s: s.update(vx=15 / 3.6 / M_PER_STUD), lambda t, s: {"throttle": 1, "lean": 1} if t < 3 else {"brake": 1}, 5, "Standard")
    ths = [math.degrees(x) for x in log["th"]]
    i3 = int(len(ths) * 3 / 5)
    down = next((log["t"][i] - 3 for i in range(i3, len(ths)) if ths[i] < 2), None)
    p(f"  pitch at 3 s {ths[i3]:.1f} deg, front down after {down if down is None else round(down, 2)} s, landing load {max(log['load'][i3:]):.2f} g")

    text = "\n".join(out)
    print(text)
    with open(os.path.join(HERE, "results_v3.txt"), "w") as fh:
        fh.write(text + "\n")


if __name__ == "__main__":
    main()
