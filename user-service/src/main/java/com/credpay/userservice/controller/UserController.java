package com.credpay.userservice.controller;

import com.credpay.userservice.dto.LoginRequest;
import com.credpay.userservice.dto.LoginResponse;
import com.credpay.userservice.dto.MessageResponse;
import com.credpay.userservice.dto.RegisterRequest;
import com.credpay.userservice.entity.User;
import com.credpay.userservice.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    // Used by the pipeline's post-deployment smoke test (GET /api/users/health).
    @GetMapping("/health")
    public ResponseEntity<MessageResponse> health() {
        return ResponseEntity.ok(new MessageResponse("UP"));
    }

    @PostMapping("/register")
    public ResponseEntity<MessageResponse> register(@Valid @RequestBody RegisterRequest request) {
        userService.register(request);
        return ResponseEntity.ok(new MessageResponse("User registered successfully"));
    }

    @PostMapping("/login")
    public ResponseEntity<LoginResponse> login(@Valid @RequestBody LoginRequest request) {
        User user = userService.login(request);
        return ResponseEntity.ok(new LoginResponse(
                user.getId(),
                user.getFullName(),
                user.getEmail(),
                "Login successful"
        ));
    }
}
