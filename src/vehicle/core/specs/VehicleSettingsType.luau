--!strict
-- La configuración que consume el simulador: las claves de las tres fichas (`SpecTypes`) y las que calcula `assemble`.
-- Es una sola tabla plana (no una intersección de tipos) para que las pruebas y los módulos puedan recorrerla.
-- Si se agrega una clave a una ficha, se agrega también acá.
local SpecTypes = require("./SpecTypes")

export type WheelSpec = SpecTypes.WheelSpec
export type TorquePoint = SpecTypes.TorquePoint

export type VehicleSettings = {
	-- Orden fijo: FL, FR, RL, RR. Las posiciones están en el marco del chasis de Roblox (-z adelante).
	WHEELS: { WheelSpec },
	WHEEL_RADIUS_STUDS: number,
	-- Masa del chasis solo (sin motor), en unidades de Roblox.
	CHASSIS_MASS: number,
	-- Dónde va el motor, en z del marco del Body (-z adelante).
	ENGINE_POSITION_Z: number,
	-- Fracción del peso del chasis solo sobre el eje delantero; `assemble` suma el motor.
	FRONT_WEIGHT_FRACTION: number,
	CENTER_OF_MASS_HEIGHT_STUDS: number,
	BALLAST_MASS_FRACTION: number,
	SUSPENSION_FREQUENCY_HZ: number,
	SUSPENSION_DAMPING_RATIO: number,
	SUSPENSION_REST_LENGTH_STUDS: number,
	SUSPENSION_MAX_COMPRESSION_STUDS: number,
	SUSPENSION_MAX_FORCE_PER_STATIC_LOAD: number,
	BOTTOM_OUT_FRACTION: number,
	BOTTOM_OUT_MAX_MISSED_STEPS: number,
	COMPRESSION_SPEED_FILTER_RATE: number,
	TIRE_FRICTION: number,
	TIRE_CORNERING_STIFFNESS_PER_RADIAN: number,
	TIRE_SLIDE_FRICTION_RATIO: number,
	LOW_SPEED_REGULARIZATION_STUDS_PER_SECOND: number,
	FRONT_GRIP_MULTIPLIER: number,
	REAR_GRIP_MULTIPLIER: number,
	HANDBRAKE_REAR_GRIP_MULTIPLIER: number,
	HANDBRAKE_GRIP_DROP_RATE: number,
	HANDBRAKE_GRIP_RECOVERY_RATE: number,
	SURFACE_GRIP: { Road: number, Shoulder: number, Grass: number, Mud: number },
	SURFACE_ROLLING_RESISTANCE: { Road: number, Shoulder: number, Grass: number, Mud: number },
	SURFACE_BLEND_RATE: number,
	AIR_DRAG_PER_SPEED_SQUARED: number,
	BRAKE_DECELERATION: number,
	BRAKE_FRONT_BIAS: number,
	HANDBRAKE_FORCE_PER_LOAD: number,
	HANDBRAKE_HOLD_FORCE_PER_LOAD: number,
	HANDBRAKE_HOLD_SPEED: number,
	HANDBRAKE_HOLD_MAX_DRIFT_DEGREES: number,
	STEER_MAX_LOW_SPEED_DEGREES: number,
	STEER_MAX_HIGH_SPEED_DEGREES: number,
	DRIFT_STEER_MARGIN_DEGREES: number,
	STEER_LOW_SPEED: number,
	STEER_HIGH_SPEED: number,
	STEER_MAX_REVERSE_DEGREES: number,
	COUNTER_STEER_STRENGTH: number,
	COUNTER_STEER_MAX_DEGREES: number,
	COUNTER_STEER_MIN_SPEED: number,
	DRIFT_ANGLE_THRESHOLD_DEGREES: number,
	DRIFT_MIN_SPEED: number,
	-- Daño (WP-15): valores por defecto que `DamageEffects` cambia, en el orden FL, FR, RL, RR.
	WHEEL_GRIP_MULTIPLIERS: { number },
	STEER_OFFSET_DEGREES: number,
	-- Torque pico en unidades de torque de juego (no son N·m).
	PEAK_TORQUE: number,
	TORQUE_CURVE: { TorquePoint },
	IDLE_RPM: number,
	REDLINE_RPM: number,
	-- Entre REDLINE_RPM − este valor y REDLINE_RPM la fuerza del motor baja linealmente hasta 0.
	SOFT_LIMITER_RPM: number,
	ENGINE_MASS: number,
	-- Desaceleración (studs/s²) en 1ra al corte con el acelerador suelto (WP-17).
	ENGINE_BRAKE_DECELERATION: number,
	ENGINE_BRAKE_MIN_RPM: number,
	-- "manual" queda previsto para después del MVP (decisión M1).
	kind: "automatic" | "manual",
	GEAR_RATIOS: { number },
	REVERSE_RATIO: number,
	REVERSE_DRIVE_FRACTION: number,
	FINAL_DRIVE: number,
	-- Fracción del torque que llega a la rueda, en (0, 1].
	DRIVETRAIN_EFFICIENCY: number,
	-- Fracción de la fuerza que va al eje trasero.
	REAR_BIAS: number,
	UPSHIFT_RPM: number,
	DOWNSHIFT_RPM: number,
	KICKDOWN_THROTTLE: number,
	KICKDOWN_ACCEL_MARGIN: number,
	UPSHIFT_ACCEL_MARGIN: number,
	KICKDOWN_MAX_RPM: number,
	LOAD_PITCH_FILTER_RATE: number,
	GEAR_HOLD_SECONDS: number,
	SHIFT_DURATION_SECONDS: number,
	SHIFT_TORQUE_FRACTION: number,
	REVERSE_ENGAGE_SPEED: number,
	-- Masa del chasis más la del motor: lo que tiene que pesar el auto armado.
	TOTAL_MASS: number,
	-- Aceleración (studs/s²) que da la 1ra a torque pico con la masa total: sale del torque del motor.
	FIRST_GEAR_PEAK_ACCELERATION: number,
	MAX_STEP_SECONDS: number,
	CONTACT_PLANE_DEGENERATE_THRESHOLD: number,
}

return {}
