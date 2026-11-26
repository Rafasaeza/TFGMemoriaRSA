# Complete Sensor Adaptation Prompt

## Role & Objective

You are an expert Systems & Robotics Engineer proficient in Rust (async Tokio, Serde, MQTT) and physical powertrain simulation. Your task is to extend the `bekirbostanci/vda5050_vehicle_simulator` repository by implementing a high-fidelity physical telemetry, dynamics, and fault-injection module.

## 1. Context & Architecture Requirements

- **Target Repository**: `bekirbostanci/vda5050_vehicle_simulator` (written in Rust).
- **Configuration Integration**: Extend the `config.toml` file to support physical motor, battery, thermal, and sensor parameters alongside existing VDA 5050 parameters. Faults have no entries in that file.
- **Protocol & Messaging**: Maintain compatibility with VDA 5050 MQTT state messages (updating `batteryState`, `velocity`, `errors`, and the extended motor telemetry inside `information`) published at the configured state frequency.

> **Implemented deviation — where the physics runs.** The first instruction asked for a dedicated async task. The integrated simulator steps the powertrain inside the same tick that advances the mission (`update_powertrain`), in fixed sub-steps of `physics.substep_s`. There is no second thread.

## 2. Physical Telemetry Channels & Equations

### Motor Armature & Torque Balance

$$
V_m(t) = R_a(T_m) \cdot I_m(t) + L_a \frac{dI_m(t)}{dt} + K_e \cdot \omega_m(t)
$$

> **Implemented deviation — $L_a$ is neglected ($L_a \approx 0$).** The armature circuit is solved algebraically as $V_m(t) = R_a(T_m) \cdot I_m(t) + K_e \cdot \omega_m(t)$. The electrical time constant $\tau_e = L_a / R_a$ is about 40 ms, short beside the mechanical constants (about 1–3 s) and the 1 Hz state report. A blocked rotor is the exception: back-EMF is zero and the chopper is fully open, so the terminal voltage is the bus voltage and the current sits on the drive limit.

$$
\tau_m(t) = K_t \cdot I_m(t)
$$

$$
J_m \frac{d\omega_m(t)}{dt} + B_m \cdot \omega_m(t) = \tau_m(t) - \frac{\tau_L(t)}{\eta_g \cdot i_g} - \tau_{\text{friction}}
$$

where the wheel load is

$$
\tau_L(t) = r_w \cdot (C_{rr} \cdot m_{total} \cdot g \cdot \cos\theta + m_{total} \cdot a(t) + m_{total} \cdot g \cdot \sin\theta + F_{drawbar})
$$

> **Implemented deviation — the shaft speed is commanded, and the balance is solved for current.** The mission layer owns the trajectory. Rotor speed is the commanded outer-wheel speed reflected through the gearbox, $\omega_m = v_w \cdot i_g / r_w$, or zero when the wheel is locked. The balance is rearranged for the current that torque requires,
>
> $$
> I_m = \frac{1}{K_t}\left(\tau_{L,\text{shaft}} + \tau_{\text{friction}} + B_m \omega_m + J_m \alpha_m\right)
> $$
>
> and then capped by the current the bus voltage can push through $R_a$ and by the drive limit. $\alpha_m$ is the commanded wheel acceleration reflected to the shaft, not a free integration of this ODE. Rolling resistance is applied only while the drivetrain is turning. Gear efficiency helps when the motor pulls the load and works against the motor when the vehicle overruns it. $\tau_{\text{friction}}$ is the sum of gearbox and bearing wear.

### Kinematics

The chassis is a differential drive. Lateral velocity is zero. Published $v_x$ is the ground speed along the heading, and $\omega$ is the yaw rate. The motor does not track $v_x$. It tracks the outer wheel of a pair with track $b$:

$$
v_w(t) = |v(t)| + |\omega(t)|\,\frac{b}{2}, \qquad v_w(t) = \frac{\omega_m(t)}{i_g} \cdot r_w.
$$

On a straight cruise $\omega = 0$, so $v_w = v_x$. During a spot turn $v = 0$ while the outer wheel, and therefore the armature, still moves with the yaw.

> **Implemented deviation — wheel wear lowers rolling resistance.** The worn tyre keeps the commanded wheel speed and the ground speed. A fraction of the new-tyre rolling resistance is removed and then stays, capped at a 20 % drop, so the same cruise draws less current. Bearing wear adds a small oscillation, about 0.3 Hz, on the tracked shaft speed. A blocked wheel sets rotor speed, yaw, and ground progress to zero.

### Thermal Dissipation Model

$$
R_a(T_m) = R_{a0} \cdot [1 + \alpha(T_m - T_0)]
$$

$$
C_{th} \frac{dT_m(t)}{dt} = I_m(t)^2 R_a(T_m) + C_{fe} \omega_m(t)^{1.6} B_{max}^2 - \frac{T_m(t) - T_{amb}}{R_{th}}
$$

$$
C_{th,bat} \frac{dT_{bat}(t)}{dt} = I_{bat}(t)^2 R_{int} - \frac{T_{bat}(t) - T_{amb}}{R_{th,bat}}
$$

Temperatures are integrated with the sub-step and clamped. There is no stator-short heating multiplier.

### Battery Equivalent Circuit Model (ECM)

$$
V_{bat}(t) = V_{ocv}(SOC) - I_{bat}(t) \cdot R_{int}(SOC, T_{bat}, SOH)
$$

$V_{ocv}$ is linear between the empty and full points. $R_{int}$ grows at low state of charge, in the cold, and with the state-of-health multiplier. Pack current is the drive power divided by the bus voltage, plus the auxiliary and quiescent draw, minus the charger current while a charge action is active.

> **Implemented deviation — the polarisation branch $V_{pol}$ is neglected.** A 1-RC branch $\frac{dV_{pol}}{dt} = -\frac{V_{pol}}{R_p C_p} + \frac{I_{bat}}{C_p}$ is not integrated. $R_{int}$ carries the whole DC sag (the parallel resistance is folded in: 0.035 + 0.015 = 0.050 Ω). The simulator is a benchmark for anomaly recognition, not a cell-accurate pack. The branch cannot be calibrated without pulse tests, it is the smaller part of the stall sag (60 A × 0.05 Ω = 3 V against about 0.9 V), and a purely ohmic pack makes an SOH fault a change of the $V$-versus-$I$ slope.

> **Implemented deviation — accelerated discharge and the depletion stop.** Coulomb counting on discharge is multiplied by `discharge_multiplier`, so a long shift fits in a shorter capture. The default in `config.toml` is 2. Charging uses `charge_rate_c` and is not multiplied. At or below `depletion_cutoff_pct` (1 % in the shipped file), if the pack is not charging, the vehicle aborts its order and will not drive until it is recharged above that cutoff. A cutoff of 0 disables the stop.

### Transducers

Before a sample is written into the state message, the physical values pass through `sensors`: Gaussian noise, ADC quantisation, a thermistor bias that walks with operating time, and a Hall-current gain that drifts per hour. The encoder speed is quantised to one count of the configured bit width per second. Housing vibration gets the same class of Gaussian noise, with $\sigma = 0.02$ mm/s.

### Housing vibration

The state carries `vibration_rms` in mm/s. A housing accelerometer samples at several kilohertz. The state is published about once per second, so the simulator does not emit that waveform. Each electrical sub-step writes the RMS, and the state message copies the last sub-step plus the transducer noise. A healthy 1 m/s cruise reads about 1.5 mm/s and follows shaft speed. It falls to zero when the shaft is stopped and the rotor is free. Bearing wear roughly doubles the cruise reading. Gearbox wear raises it by about 30 % and stays below the bearing. A fully worn tyre makes it about 10 % quieter. A locked rotor leaves a hum of about 0.9 mm/s at the 60 A drive limit. Pack resistance does not move it.

## 3. Rust Implementation Strategy

- **Modular Design**: `src/physics/` (`motor.rs`, `battery.rs`, `thermal.rs`, `sensors.rs`, `mod.rs`) and `src/faults.rs`.
- **Serde Data Structures**: `Serialize` and `Deserialize` on the configuration and on the VDA 5050 messages.
- **Noise & Transducers**: `rand` and `rand_distr`, as in the transducer step above.

## 4. Fault Injection Engine

Faults are triggered only by VDA 5050 instant actions: `injectFault`, `clearFaults`, `resetFaults`. Parameters are `faultType`, `duration`, and `intensity`. A positive duration makes a transient fault expire. A duration of 0 or less leaves a transient fault until `clearFaults`, and applies the whole damage of a degradation fault at once. Only the mechanical stall is transient. The wear faults accumulate across the injection window and then stay.

`clearFaults` ends the stall. It does not repair wear. `resetFaults` restores gearbox friction, rolling resistance, bearing friction, and the pack resistance to the as-new values.

- **Mechanical stall** (`mechanicalStall`): $\omega_m = 0$, back-EMF collapses, current goes to the drive limit, the winding heats, the bus sags, and the body stops. The rotating vibration disappears and a hum of about 0.9 mm/s remains at the drive limit. It is the only fatal fault. Transient.
- **Gearbox degradation** (`gearboxDegradation`): additive shaft friction. Steady current and equilibrium temperature rise, and housing vibration rises by about 30 % at 0.85 N·m, staying below a worn bearing. Persistent.
- **Wheel wear** (`wheelWear`): rolling resistance falls and then stays, capped at a 20 % drop. Wheel speed and ground speed are unchanged, cruise current falls, and housing vibration eases by about 10 % at that cap. Persistent.
- **Bearing degradation** (`bearingDegradation`): shaft friction grows across the injection and then stays. Tracked speed oscillates by a few percent at 0.3 Hz, which a 1 Hz sample still sees. Housing vibration roughly doubles at 0.35 N·m. Persistent.
- **Battery SOH degradation** (`batterySohDegradation`): multiplies $R_{int}$. The same current produces a deeper voltage sag, and the reported health falls as $100$ divided by that multiplier. Housing vibration is unchanged. Persistent.

Each active fault is also appended to the VDA 5050 `errors` array. The extended telemetry carries `fault_active` and the fault names.

## 5. Deliverables

- The Rust modules above, integrated into `bekirbostanci/vda5050_vehicle_simulator` and reviewed against the equations before they were kept.
- `config.toml` comments for the electromechanical, thermal, battery, and sensor parameters. No fault block.
- Unit tests for the physics step and for the VDA 5050 state serialisation.
