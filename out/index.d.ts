import Signal from "./Signal"

type BulletData = {
	HitVelocity?: Vector3
	BulletId: string
}

type EasyBulletSettings = {
	Gravity: boolean
	RenderBullet: boolean
	BulletColor: Color3
	BulletThickness: number
	FilterList: Instance[]
	FilterType: Enum.RaycastFilterType
	BulletPartProps: InstancePropertyNames<BasePart>[]
	BulletData: BulletData
}

type FireBulletsBullet = {
	Velocity: Vector3
	BarrelPosition?: Vector3
	Settings?: Partial<EasyBulletSettings>
}

type ShouldFireArrayCallback = (
	shooter: Player | undefined,
	bullets: { BarrelPosition: Vector3; Velocity: Vector3; EasyBulletSettings: EasyBulletSettings }[],
	ping: number,
) => boolean

type CustomCastCallback = (
	shooter: Player | undefined,
	lastFramePosition: Vector3,
	thisFramePosition: Vector3,
	elapsedTime: number,
	bulletData: BulletData,
) => RaycastResult

type ShouldFireCallback = (
	shooter: Player | undefined,
	barrelPosition: Vector3,
	velocity: Vector3,
	ping: number,
	easyBulletSettings: EasyBulletSettings,
) => boolean

interface EasyBullet {
	FireBullet(barrelPosition: Vector3, bulletVelocity: Vector3, easyBulletSettings?: EasyBulletSettings): void
	FireBullets(bullets: FireBulletsBullet[]): void

	BindCustomCast(castCallback: CustomCastCallback): void

	BindShouldFire(shouldFireCallback: ShouldFireCallback): void
	BindShouldFireArray(shouldFireArrayCallback: ShouldFireArrayCallback): void

	BulletFired: Signal<
		[shootingPlayer: Player | undefined, barrelPosition: Vector3, velocity: Vector3, bulletData: BulletData]
	>
	BulletHit: Signal<[shootingPlayer: Player | undefined, raycastResult: RaycastResult, bulletData: BulletData]>
	BulletHitHumanoid: Signal<
		[
			shootingPlayer: Player | undefined,
			raycastResult: RaycastResult,
			hitHumanoid: Humanoid,
			bulletData: BulletData,
		]
	>
	BulletUpdated: Signal<[lastFramePosition: Vector3, thisFramePosition: Vector3, bulletData: BulletData]>
}

interface EasyBulletConstructor {
	new (easyBulletSettings?: Partial<EasyBulletSettings>): EasyBullet
}

declare const EasyBullet: EasyBulletConstructor

export = EasyBullet
