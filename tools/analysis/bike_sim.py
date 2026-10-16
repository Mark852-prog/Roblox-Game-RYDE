"""
Offline reproduction of RYDE's BikePhysics force laws (v0.2.0).

NOT a Roblox playtest. It re-implements the maths in
src/client/Vehicle/BikePhysics.luau in two simplified planes and integrates
them the way Roblox applies them: forces are recomputed once per rendered
frame (PreSimulation) and held constant while the physics engine steps at
240 Hz. Its purpose is to expose problems that come from the force laws
themselves; the real engine (contacts, solver, network) can only be checked
in Studio.

  python3 tools/analysis/bike_sim.py            (reads voltra_spec.json)

Scenarios
  S1 settle at rest                 sag, bounce, frame-rate sensitivity
  S2 drop landing (flat, 1.5 m)     damper spike, peak load, missed contact
  S3 wheelie (lean back + throttle) effect of suspension force direction
  S4 stoppie (full front brake)     same, nose-down
  S5 step steer at 50 km/h          yaw response of the lateral grip law
"""

import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = json.load(open(os.path.join(HERE, "voltra_spec.json")))
PHYS_HZ = 240
LATERAL_STIFFNESS = 0.75
MAX_G = 12


# ---------------------------------------------------------------------------
# Pitch-plane model (x forward, y up, theta = nose-up pitch)
# ---------------------------------------------------------------------------

class Wheel:
    def __init__(self, s, z):
        self.r = s["radius"]
        self.travel = s["travel"]
        self.omega_sq = s["omegaSq"]
        self.zeta = s["dampingRatio"]
        self.share = s["loadShare"]
        self.mount_y = s["mountY"]
        self.z = z  # forward offset of the hub from the COM (studs)
        self.last_comp = 0.0
        self.grounded = False


def make_bike():
    front = Wheel(SPEC["front"], -SPEC["front"]["hubRestZ"])  # -Z is forward in Roblox
    rear = Wheel(SPEC["rear"], -SPEC["rear"]["hubRestZ"])
    box = SPEC["box"]
    mass = 1.0  # forces are mass-scaled, so unit mass is exact
    inertia = mass * (box[1] ** 2 + box[2] ** 2) / 12  # pitch inertia of the chassis box
    return front, rear, mass, inertia


def probe(wheel, cx, cy, th):
    """Sphere-cast along the body's down axis onto flat ground at y=0.
    Returns (hit, compression, bottomed, contact_x). Mirrors WheelProbe."""
    fx, fy = math.cos(th), math.sin(th)
    ux, uy = -math.sin(th), math.cos(th)
    mx = cx + fx * wheel.z + ux * wheel.mount_y
    my = cy + fy * wheel.z + uy * wheel.mount_y
    # sphere starts one radius above the mount, travels down -u by r + travel
    oy = my + uy * wheel.r
    cos = uy
    if cos <= 1e-3:
        return False, 0.0, 0.0, mx
    d = (oy - wheel.r) / cos  # distance until the sphere touches y=0
    if d < 0:
        return False, 0.0, 0.0, mx  # starts inside the ground: Spherecast misses it
    if d > wheel.r + wheel.travel:
        return False, 0.0, 0.0, mx
    hub_drop = d - wheel.r
    comp = min(max(wheel.travel - hub_drop, 0.0), wheel.travel)
    bottomed = max(-hub_drop, 0.0)
    contact_x = mx + ux * (wheel.r - d)
    return True, comp, bottomed, contact_x


def run_pitch(scenario, fps, variant, controller=None):
    """variant: 'current' or 'proposed'. controller(t, th_deg, vx) -> (throttle, brake_front, lean) or None."""
    front, rear, m, inertia = make_bike()
    g = SPEC["gravity"]
    dt_frame = 1.0 / fps
    sub = PHYS_HZ // fps
    dt = 1.0 / PHYS_HZ
    h = SPEC["comHeight"]
    x, y, th = 0.0, h, 0.0
    vx, vy, w = 0.0, 0.0, 0.0
    throttle = brake_front = lean = 0.0
    log = {"max_load_ratio": 0.0, "first_contact_damper_ratio": None, "missed_contacts": 0,
           "min_y_box": 1e9, "y": [], "th": [], "vx": [], "t": []}
    duration = 3.0
    if scenario == "S1":
        y = h + 0.5  # released slightly above rest
    elif scenario == "S2":
        y = h + 1.5 / 0.28  # 1.5 m drop
        vx = 10.0
    elif scenario == "S3":
        vx = 5.0 / 0.28  # 5 m/s
        throttle, lean = 1.0, 1.0
        duration = 2.0
    elif scenario == "S4":
        vx = (40 / 3.6) / 0.28
        brake_front, lean = 1.0, -1.0
        duration = 2.0
    drive_max = SPEC["maxDriveAccel"]
    t = 0.0
    forces = (0.0, 0.0, 0.0)
    if controller is not None:
        duration = 4.0
    while t < duration:
        if controller is not None:
            throttle, brake_front, lean = controller(t, math.degrees(th), vx)
        # ---- once per frame: compute forces (PreSimulation) ----
        Fx = Fy = tau = 0.0
        fx, fy = math.cos(th), math.sin(th)
        ux, uy = -math.sin(th), math.cos(th)
        for wheel in (front, rear):
            hit, comp, bottomed, cxp = probe(wheel, x, y, th)
            if not hit:
                if wheel.grounded and y < h:  # was on the ground, now "missed"
                    log["missed_contacts"] += 1
                wheel.grounded = False
                if variant == "current":
                    wheel.last_comp = 0.0
                continue
            corner = m * wheel.share
            k = corner * wheel.omega_sq
            c = 2 * wheel.zeta * corner * math.sqrt(wheel.omega_sq)
            if variant == "current":
                rate = (comp - wheel.last_comp) / dt_frame
            else:
                # proposed: damper from the hub's actual velocity along the suspension axis
                px = wheel.z * fx + wheel.mount_y * ux
                py = wheel.z * fy + wheel.mount_y * uy
                pvx, pvy = vx - w * py, vy + w * px
                rate = -(pvx * ux + pvy * uy) if comp > 0 else 0.0
            damper = c * rate
            if not wheel.grounded and log["first_contact_damper_ratio"] is None and scenario == "S2":
                log["first_contact_damper_ratio"] = abs(damper) / (m * g)
            wheel.grounded = True
            wheel.last_comp = comp
            susp = k * comp + damper
            if bottomed > 0:
                susp += k * 12 * bottomed + c * 2 * max(rate, 0)
            susp = min(max(susp, 0.0), m * g * MAX_G)
            log["max_load_ratio"] = max(log["max_load_ratio"], susp / (m * g))
            # longitudinal force along ground (flat) at contact
            long = 0.0
            if wheel is rear:
                long += m * drive_max * throttle
            if wheel is front and brake_front > 0:
                long -= math.copysign(min(m * SPEC["frontBrakeFull"], abs(vx) * corner / dt_frame), vx)
            long = max(-susp, min(susp, long))  # grip mu=1 on asphalt
            # suspension direction
            if variant == "current":
                sx, sy = ux * susp, uy * susp  # along chassis up (as coded)
            else:
                sx, sy = 0.0, susp  # along ground normal (proposed)
            fxw, fyw = sx + long, sy
            Fx += fxw
            Fy += fyw
            # torque about COM from force at contact point (contact at ground y=0)
            rx, ry = cxp - x, 0.0 - y
            tau += rx * fyw - ry * fxw
        tau += lean * m * SPEC["riderFraction"] * g * SPEC["riderShift"]
        forces = (Fx, Fy, tau)
        # ---- physics substeps ----
        for _ in range(sub):
            ax = forces[0] / m
            ay = forces[1] / m - g
            al = forces[2] / inertia
            vx += ax * dt
            vy += ay * dt
            w += al * dt
            x += vx * dt
            y += vy * dt
            th += w * dt
            # chassis box can't go through the ground (crude contact)
            box_bottom = y - SPEC["box"][1] / 2 * math.cos(th) - abs(SPEC["box"][2] / 2 * math.sin(th))
            log["min_y_box"] = min(log["min_y_box"], box_bottom)
            if box_bottom < 0:
                y -= box_bottom
                vy = max(vy, 0)
            t += dt
        log["t"].append(t)
        log["y"].append(y)
        log["th"].append(th)
        log["vx"].append(vx)
    return log


def oscillations(series, centre):
    crossings = 0
    for a, b in zip(series, series[1:]):
        if (a - centre) * (b - centre) < 0:
            crossings += 1
    return crossings // 2


# ---------------------------------------------------------------------------
# Yaw-plane model (top view): step steer
# ---------------------------------------------------------------------------

def run_yaw(fps, speed_kmh, steer_deg, stiffness):
    m = 1.0
    box = SPEC["box"]
    iz = m * (box[0] ** 2 + box[2] ** 2) / 12
    a = -SPEC["front"]["hubRestZ"]  # COM to front axle
    b = SPEC["rear"]["hubRestZ"]  # COM to rear axle
    g = SPEC["gravity"]
    u = (speed_kmh / 3.6) / 0.28
    v = 0.0  # lateral velocity (body frame)
    r = 0.0  # yaw rate
    delta = math.radians(steer_deg)
    dt_frame, sub, dt = 1.0 / fps, PHYS_HZ // fps, 1.0 / PHYS_HZ
    rs = []
    t = 0.0
    while t < 3.0:
        loads = (m * g * SPEC["front"]["loadShare"], m * g * SPEC["rear"]["loadShare"])
        shares = (SPEC["front"]["loadShare"], SPEC["rear"]["loadShare"])
        fy_total = 0.0
        mz = 0.0
        for i, (x_i, steer) in enumerate(((a, delta), (-b, 0.0))):
            vlat_body = v + r * x_i
            # velocity in tyre frame
            vt_lat = -u * math.sin(steer) + vlat_body * math.cos(steer)
            f = -vt_lat * (m * shares[i]) / dt_frame * stiffness
            f = max(-loads[i], min(loads[i], f))  # mu = 1
            fy = f * math.cos(steer)
            fy_total += fy
            mz += fy * x_i
        for _ in range(sub):
            v += (fy_total / m - u * r) * dt
            r += (mz / iz) * dt
            t += dt
        rs.append(r)
    steady = u * math.tan(delta) / (a + b)
    peak = max(rs, key=abs)
    tail = rs[len(rs) // 2:]
    return steady, peak, sum(tail) / len(tail), oscillations(rs, steady), max(tail) - min(tail)


def main():
    out = []
    p = out.append
    p("RYDE BikePhysics offline reproduction (model of the force laws, not a Roblox playtest)")
    p(f"Vehicle: {SPEC['id']}, gravity {SPEC['gravity']} studs/s^2, physics {PHYS_HZ} Hz\n")

    p("S1 settle at rest (released 0.5 studs high)")
    for fps in (60, 30, 20):
        for variant in ("current", "proposed"):
            log = run_pitch("S1", fps, variant)
            rest = log["y"][-1]
            p(f"  {fps:>2} fps {variant:<8}: final COM height {rest:.3f}  bounces {oscillations(log['y'], rest)}  max load {log['max_load_ratio']:.2f} g")
    p("")

    p("S2 drop landing, 1.5 m, flat, 10 studs/s forward")
    for fps in (60, 30, 20):
        for variant in ("current", "proposed"):
            log = run_pitch("S2", fps, variant)
            spike = log["first_contact_damper_ratio"]
            p(f"  {fps:>2} fps {variant:<8}: first-contact damper force {spike:.2f} x weight, peak suspension load {log['max_load_ratio']:.2f} x weight, "
              f"chassis box min clearance {log['min_y_box']:.2f} studs, missed contacts {log['missed_contacts']}")
    p("")

    # S3a: a "skilled rider" (proportional throttle on pitch error) tries to hold a 25 deg wheelie.
    def wheelie_rider(target):
        def ctrl(t, th_deg, vx):
            if t < 0.6:
                return 1.0, 0.0, 1.0  # pop it up
            err = target - th_deg
            return min(max(0.35 + 0.06 * err, 0.0), 1.0), 0.0, 0.3
        return ctrl
    p("S3a wheelie hold: rider pops the front (0.6 s), then modulates throttle to hold 25 deg")
    for fps in (60, 30):
        for variant in ("current", "proposed"):
            log = run_pitch("S3", fps, variant, wheelie_rider(25))
            ths = [math.degrees(x) for x in log["th"]]
            n = len(ths)
            hold = ths[int(n * 0.4):]
            mean = sum(hold) / len(hold)
            spread = max(hold) - min(hold)
            accel = (log["vx"][-1] - log["vx"][int(n * 0.4)]) / (log["t"][-1] - log["t"][int(n * 0.4)])
            looped = max(ths) > 90
            p(f"  {fps} fps {variant:<8}: held pitch {mean:5.1f} deg (swing {spread:5.1f}), looped out: {looped}, "
              f"forward accel during hold {accel * 0.28:5.2f} m/s^2")
    p("")

    # S3b: tap — full throttle + lean back for 0.4 s, then release everything. Does the front come back down?
    p("S3b wheelie tap: throttle + lean back for 0.4 s, then release")
    for variant in ("current", "proposed"):
        log = run_pitch("S3", 60, variant, lambda t, th, vx: (1.0, 0.0, 1.0) if t < 0.4 else (0.0, 0.0, 0.0))
        ths = [math.degrees(x) for x in log["th"]]
        p(f"  60 fps {variant:<8}: peak pitch {max(ths):5.1f} deg, pitch after 4 s {ths[-1]:5.1f} deg")
    p("")

    # S4: stoppie hold — rider modulates the front brake to hold -12 deg (rear up) from 40 km/h.
    def stoppie_rider(target):
        def ctrl(t, th_deg, vx):
            if vx <= 0.5:
                return 0.0, 0.0, 0.0
            err = th_deg - target  # positive = not enough nose-down
            return 0.0, min(max(0.55 + 0.05 * err, 0.0), 1.0), 0.0
        return ctrl
    p("S4 stoppie hold: rider modulates the front brake to hold -12 deg from 40 km/h")
    for variant in ("current", "proposed"):
        log = run_pitch("S4", 60, variant, stoppie_rider(-12))
        ths = [math.degrees(x) for x in log["th"]]
        stop_t = next((log["t"][i] for i, v in enumerate(log["vx"]) if v <= 0.5), None)
        p(f"  60 fps {variant:<8}: lowest pitch {min(ths):6.1f} deg, flipped: {min(ths) < -80}, stopped after {stop_t} s")
    p("")

    p("S5 step steer (yaw response); steady-state target = kinematic yaw rate v*tan(d)/L")
    for speed, steer in ((15, 20), (50, 3)):
        for fps in (60, 30):
            for stiff in (LATERAL_STIFFNESS, 0.35):
                steady, peak, mean_tail, osc, ripple = run_yaw(fps, speed, steer, stiff)
                tag = "current" if stiff == LATERAL_STIFFNESS else "softer"
                p(f"  {speed} km/h, {steer} deg, {fps} fps, stiffness {stiff:.2f} ({tag}): target {steady:.3f} rad/s, "
                  f"peak {peak:.3f}, settled {mean_tail:.3f}, oscillations {osc}, ripple {ripple:.3f}")
    text = "\n".join(out)
    print(text)
    with open(os.path.join(HERE, "results.txt"), "w") as fh:
        fh.write(text + "\n")


if __name__ == "__main__":
    main()
