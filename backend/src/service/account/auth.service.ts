import { BadRequestException, ConflictException, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { DataSource } from 'typeorm';
import { AuthUser } from '../../common/security/security';
import { AccountDao } from '../../dao/dao';
import { LoginDto, RegisterDto } from '../../dto/dto';
import { Customer, User } from '../../model/entities';
import { NotificationService } from '../common/notification.service';

const MAX_FAILED = 5;          // NFR-5
const LOCK_MINUTES = 15;

@Injectable()
export class AuthService {
  constructor(
    private readonly dao: AccountDao, private readonly jwt: JwtService, private readonly ds: DataSource, private readonly notifier: NotificationService,
  ) {}

  /* ================================================================ UC01 Register Account */
  async register(dto: RegisterDto) {
    if (dto.password !== dto.confirmPassword) throw new BadRequestException('Mật khẩu nhập lại không khớp');
    return this.ds.transaction(async (m) => {
      const taken = await this.dao.emailOrPhoneTaken(m, dto.email, dto.phone);                            // BR2 – 01.E2
      if (taken.email || taken.phone) {
        throw new ConflictException(
          [taken.email && 'Email đã được đăng ký', taken.phone && 'Số điện thoại đã được đăng ký'].filter(Boolean).join('; ') + '. Vui lòng dùng thông tin khác.');
      }
      const user = await m.getRepository(User).save(m.getRepository(User).create({
        roleId: await this.dao.customerRoleId(m), email: dto.email.toLowerCase(), phone: dto.phone, fullName: dto.fullName,
        passwordHash: await bcrypt.hash(dto.password, 10),                                                   // BR1
        status: 'ACTIVE', failedLoginCount: 0, lockedUntil: null, lastLoginAt: null, updatedAt: new Date(),
      }));
      const customer = await m.getRepository(Customer).save(m.getRepository(Customer).create({ userId: user.userId, address: null }));
      await this.notifier.notify(m, [user.userId], 'Chào mừng đến AutoCare', 'Tài khoản đã được tạo. Hãy thêm xe và đặt lịch dịch vụ.', 'USER', user.userId);
      await this.notifier.audit(m, user.userId, 'ACCOUNT_REGISTERED', 'users', user.userId, { email: user.email, phone: user.phone });
      return { userId: user.userId, customerId: customer.customerId, email: user.email, fullName: user.fullName };
    });
  }

  /* ================================================================ UC02 Login */
  async login(dto: LoginDto) {
    const acc = await this.dao.findLoginByEmailOrPhone(dto.login);
    if (!acc) throw new UnauthorizedException('Email/số điện thoại hoặc mật khẩu không đúng');
    const users = this.ds.getRepository(User);
    if (acc.lockedUntil && new Date(acc.lockedUntil) > new Date()) {
      throw new ForbiddenException(`Tài khoản tạm khóa đến ${new Date(acc.lockedUntil).toLocaleTimeString('vi-VN')} do nhập sai mật khẩu nhiều lần`);
    }
    if (acc.status === 'INACTIVE') throw new ForbiddenException('Tài khoản đã bị vô hiệu hóa');               // BR3

    if (!(await bcrypt.compare(dto.password, acc.passwordHash))) {
      const failed = acc.failedLoginCount + 1;
      const lock = failed >= MAX_FAILED;
      await users.update(acc.userId, {
        failedLoginCount: lock ? 0 : failed, lockedUntil: lock ? new Date(Date.now() + LOCK_MINUTES * 60_000) : null, updatedAt: new Date(),
      });
      throw new UnauthorizedException(lock
        ? `Sai mật khẩu ${MAX_FAILED} lần, tài khoản bị khóa ${LOCK_MINUTES} phút`
        : `Email/số điện thoại hoặc mật khẩu không đúng (còn ${MAX_FAILED - failed} lần thử)`);
    }
    await users.update(acc.userId, { failedLoginCount: 0, lockedUntil: null, status: 'ACTIVE', lastLoginAt: new Date(), updatedAt: new Date() });

    const user: AuthUser = {                                                                                // BR4 – role & data scope
      userId: acc.userId, fullName: acc.fullName, role: acc.role, staffId: acc.staffId ?? null, branchId: acc.branchId ?? null, customerId: acc.customerId ?? null,
    };
    return { accessToken: this.jwt.sign(user), user: { ...user, email: acc.email, phone: acc.phone, branchName: acc.branchName ?? null } };
  }

  notifications(user: AuthUser) {
    return this.dao.myNotifications(user.userId);
  }
}
